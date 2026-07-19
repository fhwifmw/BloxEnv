cmake_minimum_required(VERSION 3.20)

project(BloxEnv VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
set(LUAU_WERROR OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    luau
    GIT_REPOSITORY https://github.com/luau-lang/luau.git
    GIT_TAG 0.730
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(luau)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/runtime/bootstrap.luau" BLOXENV_BOOTSTRAP_SOURCE)
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/EmbeddedRuntime.hpp.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/EmbeddedRuntime.hpp"
    @ONLY
)

add_executable(bloxenv src/main.cpp)
target_include_directories(bloxenv PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(bloxenv PRIVATE Luau.Compiler Luau.VM)

if(MSVC)
    target_compile_options(bloxenv PRIVATE /W4 /permissive-)
else()
    target_compile_options(bloxenv PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS bloxenv RUNTIME DESTINATION bin)
