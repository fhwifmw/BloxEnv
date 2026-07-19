#include "EmbeddedRuntime.hpp"

#include "lua.h"
#include "lualib.h"
#include "luacode.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace
{
constexpr const char* kVersion = "0.1.0";

struct Options
{
    fs::path scriptPath;
    std::optional<fs::path> configPath;
    bool disableConfig = false;
    bool strict = false;
    bool allowOutsideRoot = false;
    std::vector<std::string> scriptArguments;
};

std::string readTextFile(const fs::path& path)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error("Unable to open " + path.string());

    std::ostringstream contents;
    contents << stream.rdbuf();
    if (!stream.good() && !stream.eof())
        throw std::runtime_error("Unable to read " + path.string());

    return contents.str();
}

fs::path canonicalExistingFile(const fs::path& input, const char* label)
{
    std::error_code error;
    fs::path absolute = fs::absolute(input, error);
    if (error)
        throw std::runtime_error(std::string("Unable to resolve ") + label + ": " + input.string());

    fs::path candidates[] = {
        absolute,
        fs::path(absolute.string() + ".luau"),
        fs::path(absolute.string() + ".lua"),
    };

    for (const fs::path& candidate : candidates)
    {
        if (fs::is_regular_file(candidate, error) && !error)
            return fs::weakly_canonical(candidate);
        error.clear();
    }

    throw std::runtime_error(std::string(label) + " does not exist: " + input.string());
}

std::optional<fs::path> findNearestConfig(const fs::path& scriptPath)
{
    fs::path directory = scriptPath.parent_path();

    while (!directory.empty())
    {
        fs::path candidate = directory / "bloxenv.config.luau";
        std::error_code error;
        if (fs::is_regular_file(candidate, error) && !error)
            return fs::weakly_canonical(candidate);

        fs::path parent = directory.parent_path();
        if (parent == directory)
            break;
        directory = parent;
    }

    return std::nullopt;
}

fs::path commonAncestor(fs::path first, fs::path second)
{
    first = fs::weakly_canonical(first);
    second = fs::weakly_canonical(second);

    auto firstIt = first.begin();
    auto secondIt = second.begin();
    fs::path result;

    while (firstIt != first.end() && secondIt != second.end() && *firstIt == *secondIt)
    {
        result /= *firstIt;
        ++firstIt;
        ++secondIt;
    }

    return result.empty() ? first.root_path() : result;
}

bool isWithin(const fs::path& root, const fs::path& path)
{
    fs::path relative = path.lexically_relative(root);
    if (relative.empty())
        return path == root;

    auto first = relative.begin();
    return first == relative.end() || *first != "..";
}

void printUsage(std::ostream& output)
{
    output
        << "BloxEnv " << kVersion << "\n"
        << "Run Roblox-oriented Luau code in a configurable local environment.\n\n"
        << "Usage:\n"
        << "  bloxenv [options] <script.luau> [-- script arguments...]\n\n"
        << "Options:\n"
        << "  --config <path>       Use a specific config file\n"
        << "  --no-config           Do not search for bloxenv.config.luau\n"
        << "  --strict              Error on unsupported services\n"
        << "  --allow-outside-root  Allow require() to read modules outside the project root\n"
        << "  -h, --help            Show this help\n"
        << "  -v, --version         Show the version\n";
}

Options parseArguments(int argc, char** argv)
{
    Options options;
    bool collectingScriptArguments = false;

    for (int index = 1; index < argc; ++index)
    {
        std::string argument = argv[index];

        if (collectingScriptArguments)
        {
            options.scriptArguments.push_back(argument);
            continue;
        }

        if (argument == "--")
        {
            collectingScriptArguments = true;
        }
        else if (argument == "-h" || argument == "--help")
        {
            printUsage(std::cout);
            std::exit(0);
        }
        else if (argument == "-v" || argument == "--version")
        {
            std::cout << "BloxEnv " << kVersion << '\n';
            std::exit(0);
        }
        else if (argument == "--strict")
        {
            options.strict = true;
        }
        else if (argument == "--allow-outside-root")
        {
            options.allowOutsideRoot = true;
        }
        else if (argument == "--no-config")
        {
            options.disableConfig = true;
        }
        else if (argument == "--config")
        {
            if (index + 1 >= argc)
                throw std::runtime_error("--config requires a path");
            options.configPath = fs::path(argv[++index]);
        }
        else if (!argument.empty() && argument[0] == '-')
        {
            throw std::runtime_error("Unknown option: " + argument);
        }
        else if (options.scriptPath.empty())
        {
            options.scriptPath = fs::path(argument);
        }
        else
        {
            throw std::runtime_error("Unexpected argument: " + argument + " (use -- before script arguments)");
        }
    }

    if (options.scriptPath.empty())
        throw std::runtime_error("No script supplied");
    if (options.disableConfig && options.configPath)
        throw std::runtime_error("--config and --no-config cannot be used together");

    options.scriptPath = canonicalExistingFile(options.scriptPath, "Script");

    if (options.configPath)
        options.configPath = canonicalExistingFile(*options.configPath, "Config");
    else if (!options.disableConfig)
        options.configPath = findNearestConfig(options.scriptPath);

    return options;
}

class Runtime
{
public:
    explicit Runtime(Options options)
        : options_(std::move(options))
    {
        if (options_.configPath)
            projectRoot_ = commonAncestor(options_.scriptPath.parent_path(), options_.configPath->parent_path());
        else
            projectRoot_ = options_.scriptPath.parent_path();

        state_ = luaL_newstate();
        if (!state_)
            throw std::runtime_error("Unable to create Luau state");

        luaL_openlibs(state_);

        // BloxEnv intentionally keeps one mutable global environment so the
        // project config can replace globals and service methods at runtime.
        // Do not treat v0.1 as a hostile-code sandbox.
        registerHostGlobals();
    }

    ~Runtime()
    {
        if (state_)
            lua_close(state_);
    }

    Runtime(const Runtime&) = delete;
    Runtime& operator=(const Runtime&) = delete;

    void run()
    {
        runSource(bloxenv::kBootstrapSource, "@bloxenv/bootstrap.luau", 0, 0);

        if (options_.configPath)
        {
            loadBoundFile(*options_.configPath, "ModuleScript");
            protectedCall(0, 1, "Unable to run BloxEnv config");
            if (!lua_istable(state_, -1))
            {
                lua_pop(state_, 1);
                throw std::runtime_error("bloxenv.config.luau must return a table");
            }
        }
        else
        {
            lua_newtable(state_);
        }

        lua_setglobal(state_, "__BLOXENV_PENDING_CONFIG");
        pushBloxEnvFunction("_applyConfig");
        lua_getglobal(state_, "__BLOXENV_PENDING_CONFIG");
        protectedCall(1, 0, "Unable to apply BloxEnv config");
        lua_pushnil(state_);
        lua_setglobal(state_, "__BLOXENV_PENDING_CONFIG");

        pushBloxEnvFunction("_execute");
        loadBoundFile(options_.scriptPath, scriptClassName(options_.scriptPath));
        protectedCall(1, 0, "Target script failed");
    }

private:
    static Runtime* fromUpvalue(lua_State* state)
    {
        return static_cast<Runtime*>(lua_touserdata(state, lua_upvalueindex(1)));
    }

    static int loadModuleCallback(lua_State* state)
    {
        Runtime* runtime = fromUpvalue(state);
        try
        {
            size_t requestLength = 0;
            const char* requestValue = luaL_checklstring(state, 1, &requestLength);
            std::string request(requestValue, requestLength);

            std::string basePath;
            if (lua_gettop(state) >= 2 && lua_isstring(state, 2))
            {
                size_t baseLength = 0;
                const char* baseValue = lua_tolstring(state, 2, &baseLength);
                basePath.assign(baseValue, baseLength);
            }

            fs::path modulePath = runtime->resolveModule(request, basePath);
            runtime->loadChunk(readTextFile(modulePath), "@" + modulePath.generic_string());
            lua_pushstring(state, modulePath.generic_string().c_str());
            return 2;
        }
        catch (const std::exception& error)
        {
            luaL_error(state, "%s", error.what());
            return 0;
        }
    }

    void registerHostGlobals()
    {
        lua_pushlightuserdata(state_, this);
        lua_pushcclosure(state_, &Runtime::loadModuleCallback, "_bloxenv_loadmodule", 1);
        lua_setglobal(state_, "_bloxenv_loadmodule");

        lua_pushstring(state_, options_.scriptPath.generic_string().c_str());
        lua_setglobal(state_, "__BLOXENV_TARGET_PATH");

        lua_pushboolean(state_, options_.strict ? 1 : 0);
        lua_setglobal(state_, "__BLOXENV_STRICT");

        lua_createtable(state_, static_cast<int>(options_.scriptArguments.size()), 0);
        for (size_t index = 0; index < options_.scriptArguments.size(); ++index)
        {
            lua_pushstring(state_, options_.scriptArguments[index].c_str());
            lua_rawseti(state_, -2, static_cast<int>(index + 1));
        }
        lua_setglobal(state_, "__BLOXENV_ARGS");
    }

    void loadChunk(const std::string& source, const std::string& chunkName)
    {
        size_t bytecodeSize = 0;
        char* bytecode = luau_compile(source.data(), source.size(), nullptr, &bytecodeSize);
        if (!bytecode)
            throw std::runtime_error("Luau compiler returned no bytecode for " + chunkName);

        int status = luau_load(state_, chunkName.c_str(), bytecode, bytecodeSize, 0);
        std::free(bytecode);

        if (status != 0)
            throw std::runtime_error(popError("Unable to compile/load " + chunkName));
    }

    void runSource(const std::string& source, const std::string& chunkName, int arguments, int results)
    {
        loadChunk(source, chunkName);
        protectedCall(arguments, results, "Unable to run " + chunkName);
    }

    void loadBoundFile(const fs::path& path, const char* className)
    {
        loadChunk(readTextFile(path), "@" + path.generic_string());

        // Turn the loaded chunk into the first argument to BloxEnv._bindChunk.
        pushBloxEnvFunction("_bindChunk");
        lua_insert(state_, -2);
        lua_pushstring(state_, path.generic_string().c_str());
        lua_pushstring(state_, className);
        protectedCall(3, 1, "Unable to bind script environment");
    }

    void protectedCall(int argumentCount, int resultCount, const std::string& context)
    {
        int status = lua_pcall(state_, argumentCount, resultCount, 0);
        if (status != 0)
            throw std::runtime_error(popError(context));
    }

    std::string popError(const std::string& context)
    {
        const char* message = lua_tostring(state_, -1);
        std::string result = context;
        result += ": ";
        result += message ? message : "unknown Luau error";
        lua_pop(state_, 1);
        return result;
    }

    void pushBloxEnvFunction(const char* functionName)
    {
        lua_getglobal(state_, "BloxEnv");
        if (!lua_istable(state_, -1))
        {
            lua_pop(state_, 1);
            throw std::runtime_error("BloxEnv bootstrap did not create the BloxEnv table");
        }

        lua_getfield(state_, -1, functionName);
        lua_remove(state_, -2);

        if (!lua_isfunction(state_, -1))
        {
            lua_pop(state_, 1);
            throw std::runtime_error(std::string("BloxEnv bootstrap is missing ") + functionName);
        }
    }

    fs::path resolveModule(const std::string& request, const std::string& basePath) const
    {
        fs::path requested(request);
        fs::path baseDirectory = options_.scriptPath.parent_path();

        if (!basePath.empty())
        {
            fs::path base(basePath);
            if (base.has_filename())
                baseDirectory = base.parent_path();
            else
                baseDirectory = base;
        }

        fs::path initial = requested.is_absolute() ? requested : baseDirectory / requested;
        std::vector<fs::path> candidates;
        candidates.push_back(initial);

        if (!initial.has_extension())
        {
            candidates.emplace_back(initial.string() + ".luau");
            candidates.emplace_back(initial.string() + ".lua");
        }

        candidates.push_back(initial / "init.luau");
        candidates.push_back(initial / "init.lua");

        std::error_code error;
        for (const fs::path& candidate : candidates)
        {
            if (!fs::is_regular_file(candidate, error) || error)
            {
                error.clear();
                continue;
            }

            fs::path canonical = fs::weakly_canonical(candidate);
            if (!options_.allowOutsideRoot && !isWithin(projectRoot_, canonical))
            {
                throw std::runtime_error(
                    "require() blocked access outside project root: " + canonical.string() +
                    " (pass --allow-outside-root to allow it)"
                );
            }

            return canonical;
        }

        throw std::runtime_error(
            "Unable to resolve module '" + request + "' relative to " + baseDirectory.string()
        );
    }

    static const char* scriptClassName(const fs::path& path)
    {
        const std::string filename = path.filename().string();
        if (filename.find(".client.") != std::string::npos)
            return "LocalScript";
        if (filename.find(".module.") != std::string::npos)
            return "ModuleScript";
        return "Script";
    }

    Options options_;
    fs::path projectRoot_;
    lua_State* state_ = nullptr;
};
} // namespace

int main(int argc, char** argv)
{
    try
    {
        Options options = parseArguments(argc, argv);
        Runtime runtime(std::move(options));
        runtime.run();
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "BloxEnv error: " << error.what() << '\n';
        return 1;
    }
}
