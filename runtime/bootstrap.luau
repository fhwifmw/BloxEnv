-- BloxEnv runtime bootstrap
-- Loaded before bloxenv.config.luau and the target script.

local hostTypeof = typeof
local env = getfenv(0)

local BloxEnv = {
    version = "0.1.0",
    config = {},
    args = __BLOXENV_ARGS or {},
}

env.BloxEnv = BloxEnv

-- Deterministic scheduler -----------------------------------------------------

local scheduler = {
    now = 0,
    nextOrder = 0,
    queue = {},
    cancelled = setmetatable({}, { __mode = "k" }),
    maxSteps = 100000,
    onAdvance = nil,
}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpackPacked(values)
    return table.unpack(values, 1, values.n)
end

local function enqueue(thread, dueTime, arguments)
    scheduler.nextOrder += 1
    table.insert(scheduler.queue, {
        thread = thread,
        dueTime = dueTime,
        order = scheduler.nextOrder,
        arguments = arguments or pack(),
    })
end

local function sortQueue()
    table.sort(scheduler.queue, function(a, b)
        if a.dueTime == b.dueTime then
            return a.order < b.order
        end
        return a.dueTime < b.dueTime
    end)
end

local taskLibrary = {}

function taskLibrary.spawn(callback, ...)
    local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
    enqueue(thread, scheduler.now, pack(...))
    return thread
end

function taskLibrary.defer(callback, ...)
    local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
    enqueue(thread, scheduler.now, pack(...))
    return thread
end

function taskLibrary.delay(delaySeconds, callback, ...)
    assert(type(delaySeconds) == "number", "task.delay delay must be a number")
    assert(delaySeconds >= 0, "task.delay delay must not be negative")

    local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
    enqueue(thread, scheduler.now + delaySeconds, pack(...))
    return thread
end

function taskLibrary.wait(delaySeconds)
    local delay = delaySeconds or (1 / 30)
    assert(type(delay) == "number", "task.wait delay must be a number")
    assert(delay >= 0, "task.wait delay must not be negative")

    return coroutine.yield({
        __bloxenvWait = "time",
        delay = delay,
    })
end

function taskLibrary.cancel(thread)
    assert(type(thread) == "thread", "task.cancel expects a thread")
    scheduler.cancelled[thread] = true
end

function taskLibrary.synchronize()
    return nil
end

function taskLibrary.desynchronize()
    return nil
end

env.task = taskLibrary

-- Signals --------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
    self.Connected = false
end

Connection.disconnect = Connection.Disconnect

function Signal.new()
    return setmetatable({
        _connections = {},
        _waiters = {},
    }, Signal)
end

function Signal:Connect(callback)
    assert(type(callback) == "function", "Signal:Connect expects a function")

    local connection = setmetatable({
        Connected = true,
        _callback = callback,
    }, Connection)

    table.insert(self._connections, connection)
    return connection
end

Signal.connect = Signal.Connect

function Signal:Once(callback)
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    return connection
end

function Signal:Fire(...)
    local arguments = pack(...)

    for _, connection in ipairs(table.clone(self._connections)) do
        if connection.Connected then
            taskLibrary.spawn(connection._callback, unpackPacked(arguments))
        end
    end

    local waiters = self._waiters
    self._waiters = {}
    for _, thread in ipairs(waiters) do
        enqueue(thread, scheduler.now, arguments)
    end
end

Signal.fire = Signal.Fire

function Signal:Wait()
    return coroutine.yield({
        __bloxenvWait = "signal",
        signal = self,
    })
end

Signal.wait = Signal.Wait

function Signal:DisconnectAll()
    for _, connection in ipairs(self._connections) do
        connection.Connected = false
    end
    table.clear(self._connections)
end

local function resumeScheduled(item)
    local thread = item.thread
    if scheduler.cancelled[thread] then
        return
    end

    local ok, yielded = coroutine.resume(thread, unpackPacked(item.arguments))
    if not ok then
        local traceback = debug.traceback(thread)
        error(tostring(yielded) .. "\n" .. traceback, 0)
    end

    if coroutine.status(thread) == "dead" then
        return
    end

    if type(yielded) == "table" and yielded.__bloxenvWait == "signal" then
        local interval = yielded.signal._bloxenvInterval
        if interval then
            enqueue(thread, scheduler.now + interval, pack(interval))
        else
            table.insert(yielded.signal._waiters, thread)
        end
        return
    end

    local delay = 0
    if type(yielded) == "table" and yielded.__bloxenvWait == "time" then
        delay = yielded.delay
    elseif type(yielded) == "number" then
        delay = yielded
    end

    enqueue(thread, scheduler.now + delay, pack(delay))
end

function BloxEnv.runUntilIdle(maxSteps)
    local limit = maxSteps or scheduler.maxSteps
    local steps = 0

    while #scheduler.queue > 0 do
        steps += 1
        if steps > limit then
            error(string.format(
                "BloxEnv scheduler exceeded %d steps. The script may contain an infinite task loop.",
                limit
            ), 2)
        end

        sortQueue()
        local item = table.remove(scheduler.queue, 1)

        if item.dueTime > scheduler.now then
            local previous = scheduler.now
            scheduler.now = item.dueTime
            if scheduler.onAdvance then
                scheduler.onAdvance(scheduler.now - previous)
            end
        end

        resumeScheduled(item)
    end

    return steps
end

function BloxEnv.step(deltaTime)
    assert(type(deltaTime) == "number" and deltaTime >= 0, "BloxEnv.step expects a non-negative number")

    local targetTime = scheduler.now + deltaTime
    while true do
        sortQueue()
        local nextItem = scheduler.queue[1]
        if not nextItem or nextItem.dueTime > targetTime then
            break
        end

        table.remove(scheduler.queue, 1)
        local previous = scheduler.now
        scheduler.now = nextItem.dueTime
        if scheduler.onAdvance then
            scheduler.onAdvance(scheduler.now - previous)
        end
        resumeScheduled(nextItem)
    end

    local previous = scheduler.now
    scheduler.now = targetTime
    if scheduler.onAdvance and targetTime > previous then
        scheduler.onAdvance(targetTime - previous)
    end
end

function BloxEnv.time()
    return scheduler.now
end

env.time = function()
    return scheduler.now
end

env.tick = function()
    return scheduler.now
end

-- Roblox-like Instances ------------------------------------------------------

local classParents = {
    DataModel = "Instance",
    Workspace = "Instance",
    Players = "Instance",
    Player = "Instance",
    ReplicatedStorage = "Instance",
    ServerStorage = "Instance",
    RunService = "Instance",
    HttpService = "Instance",
    CollectionService = "Instance",
    Folder = "Instance",
    Script = "LuaSourceContainer",
    LocalScript = "Script",
    ModuleScript = "LuaSourceContainer",
    LuaSourceContainer = "Instance",
    BindableEvent = "Instance",
    BindableFunction = "Instance",
    Model = "Instance",
    Part = "BasePart",
    MeshPart = "BasePart",
    BasePart = "PVInstance",
    PVInstance = "Instance",
}

local InstanceMethods = {}
local instanceMetatable = {}

local function isInstance(value)
    return type(value) == "table" and rawget(value, "__bloxenvType") == "Instance"
end

local function fireChanged(instance, propertyName)
    local props = rawget(instance, "_props")
    props.Changed:Fire(propertyName)

    local signal = rawget(instance, "_propertySignals")[propertyName]
    if signal then
        signal:Fire()
    end
end

local function removeChild(parent, child)
    if not parent then
        return
    end

    local children = rawget(parent, "_children")
    for index, candidate in ipairs(children) do
        if candidate == child then
            table.remove(children, index)
            parent.ChildRemoved:Fire(child)
            break
        end
    end
end

local function isAncestor(candidate, object)
    local current = object
    while current do
        if current == candidate then
            return true
        end
        current = current.Parent
    end
    return false
end

local function setParent(instance, newParent)
    if newParent ~= nil and not isInstance(newParent) then
        error("Instance.Parent must be another Instance or nil", 3)
    end

    if newParent == instance or (newParent and isAncestor(instance, newParent)) then
        error("Attempt to set Instance.Parent would create a cycle", 3)
    end

    local props = rawget(instance, "_props")
    local previousParent = props.Parent
    if previousParent == newParent then
        return
    end

    removeChild(previousParent, instance)
    props.Parent = newParent

    if newParent then
        table.insert(rawget(newParent, "_children"), instance)
        newParent.ChildAdded:Fire(instance)
    end

    props.AncestryChanged:Fire(instance, newParent)
    fireChanged(instance, "Parent")
end

function instanceMetatable.__index(instance, key)
    local props = rawget(instance, "_props")
    local propertyValue = props[key]
    if propertyValue ~= nil then
        return propertyValue
    end

    local method = InstanceMethods[key]
    if method ~= nil then
        return method
    end

    for _, child in ipairs(rawget(instance, "_children")) do
        if child.Name == key then
            return child
        end
    end

    return nil
end

function instanceMetatable.__newindex(instance, key, value)
    if string.sub(key, 1, 1) == "_" or key == "__bloxenvType" then
        rawset(instance, key, value)
        return
    end

    if key == "Parent" then
        setParent(instance, value)
        return
    end

    local props = rawget(instance, "_props")
    props[key] = value
    fireChanged(instance, key)
end

function instanceMetatable.__tostring(instance)
    return instance.Name
end

local function createInstance(className)
    assert(type(className) == "string" and className ~= "", "Instance.new expects a class name")

    local object = setmetatable({
        __bloxenvType = "Instance",
        _children = {},
        _attributes = {},
        _propertySignals = {},
        _props = {},
    }, instanceMetatable)

    local props = rawget(object, "_props")
    props.Name = className
    props.ClassName = className
    props.Parent = nil
    props.Archivable = true
    props.ChildAdded = Signal.new()
    props.ChildRemoved = Signal.new()
    props.AncestryChanged = Signal.new()
    props.Changed = Signal.new()
    props.Destroying = Signal.new()

    if className == "BindableEvent" then
        props.Event = Signal.new()
        props.Fire = function(self, ...)
            self.Event:Fire(...)
        end
    end

    return object
end

local Instance = {}

function Instance.new(className, parent)
    local object = createInstance(className)
    if parent ~= nil then
        object.Parent = parent
    end
    return object
end

env.Instance = Instance
BloxEnv.Signal = Signal

function InstanceMethods:IsA(className)
    if self.ClassName == className then
        return true
    end

    local current = classParents[self.ClassName]
    while current do
        if current == className then
            return true
        end
        current = classParents[current]
    end

    return className == "Instance"
end

function InstanceMethods:GetChildren()
    return table.clone(rawget(self, "_children"))
end

function InstanceMethods:GetDescendants()
    local result = {}

    local function visit(object)
        for _, child in ipairs(rawget(object, "_children")) do
            table.insert(result, child)
            visit(child)
        end
    end

    visit(self)
    return result
end

function InstanceMethods:FindFirstChild(name, recursive)
    for _, child in ipairs(rawget(self, "_children")) do
        if child.Name == name then
            return child
        end
    end

    if recursive then
        for _, child in ipairs(rawget(self, "_children")) do
            local found = child:FindFirstChild(name, true)
            if found then
                return found
            end
        end
    end

    return nil
end

function InstanceMethods:FindFirstChildOfClass(className)
    for _, child in ipairs(rawget(self, "_children")) do
        if child:IsA(className) then
            return child
        end
    end
    return nil
end

function InstanceMethods:FindFirstChildWhichIsA(className, recursive)
    for _, child in ipairs(rawget(self, "_children")) do
        if child:IsA(className) then
            return child
        end
    end

    if recursive then
        for _, child in ipairs(rawget(self, "_children")) do
            local found = child:FindFirstChildWhichIsA(className, true)
            if found then
                return found
            end
        end
    end

    return nil
end

function InstanceMethods:WaitForChild(name, timeout)
    local existing = self:FindFirstChild(name)
    if existing then
        return existing
    end

    if timeout ~= nil then
        assert(type(timeout) == "number" and timeout >= 0, "WaitForChild timeout must be non-negative")
        local deadline = scheduler.now + timeout
        while scheduler.now < deadline do
            local remaining = deadline - scheduler.now
            taskLibrary.wait(math.min(1 / 30, remaining))
            existing = self:FindFirstChild(name)
            if existing then
                return existing
            end
        end
        return nil
    end

    while true do
        local child = self.ChildAdded:Wait()
        if child.Name == name then
            return child
        end
    end
end

function InstanceMethods:FindFirstAncestor(name)
    local current = self.Parent
    while current do
        if current.Name == name then
            return current
        end
        current = current.Parent
    end
    return nil
end

function InstanceMethods:FindFirstAncestorOfClass(className)
    local current = self.Parent
    while current do
        if current.ClassName == className then
            return current
        end
        current = current.Parent
    end
    return nil
end

function InstanceMethods:FindFirstAncestorWhichIsA(className)
    local current = self.Parent
    while current do
        if current:IsA(className) then
            return current
        end
        current = current.Parent
    end
    return nil
end

function InstanceMethods:IsDescendantOf(ancestor)
    return isAncestor(ancestor, self.Parent)
end

function InstanceMethods:GetFullName()
    local names = { self.Name }
    local current = self.Parent

    while current and current.ClassName ~= "DataModel" do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end

    return table.concat(names, ".")
end

function InstanceMethods:GetPropertyChangedSignal(propertyName)
    local signals = rawget(self, "_propertySignals")
    if not signals[propertyName] then
        signals[propertyName] = Signal.new()
    end
    return signals[propertyName]
end

function InstanceMethods:SetAttribute(name, value)
    rawget(self, "_attributes")[name] = value
end

function InstanceMethods:GetAttribute(name)
    return rawget(self, "_attributes")[name]
end

function InstanceMethods:GetAttributes()
    return table.clone(rawget(self, "_attributes"))
end

function InstanceMethods:Clone()
    if not self.Archivable then
        return nil
    end

    local clone = createInstance(self.ClassName)
    for key, value in pairs(rawget(self, "_props")) do
        if key ~= "Parent"
            and key ~= "ChildAdded"
            and key ~= "ChildRemoved"
            and key ~= "AncestryChanged"
            and key ~= "Changed"
            and key ~= "Destroying"
        then
            clone[key] = value
        end
    end

    for key, value in pairs(rawget(self, "_attributes")) do
        clone:SetAttribute(key, value)
    end

    for _, child in ipairs(rawget(self, "_children")) do
        local childClone = child:Clone()
        if childClone then
            childClone.Parent = clone
        end
    end

    return clone
end

function InstanceMethods:Destroy()
    self.Destroying:Fire()

    for _, child in ipairs(table.clone(rawget(self, "_children"))) do
        child:Destroy()
    end

    self.Parent = nil
    rawget(self, "_props").Destroyed = true
end

-- Lightweight Roblox datatypes ---------------------------------------------

local function createVectorType(typeName, componentNames)
    local methods = {}
    local metatable = {}

    function metatable.__index(value, key)
        if key == "Magnitude" then
            local sum = 0
            for _, componentName in ipairs(componentNames) do
                sum += value[componentName] * value[componentName]
            end
            return math.sqrt(sum)
        elseif key == "Unit" then
            local magnitude = metatable.__index(value, "Magnitude")
            if magnitude == 0 then
                local zeroes = {}
                for _ = 1, #componentNames do
                    table.insert(zeroes, 0)
                end
                return methods.new(table.unpack(zeroes))
            end
            return value / magnitude
        end

        return methods[key]
    end

    function metatable.__add(a, b)
        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, a[componentName] + b[componentName])
        end
        return methods.new(table.unpack(values))
    end

    function metatable.__sub(a, b)
        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, a[componentName] - b[componentName])
        end
        return methods.new(table.unpack(values))
    end

    function metatable.__unm(a)
        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, -a[componentName])
        end
        return methods.new(table.unpack(values))
    end

    function metatable.__mul(a, b)
        local vector = if type(a) == "number" then b else a
        local scalar = if type(a) == "number" then a else b
        assert(type(scalar) == "number", typeName .. " multiplication expects a scalar")

        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, vector[componentName] * scalar)
        end
        return methods.new(table.unpack(values))
    end

    function metatable.__div(a, scalar)
        assert(type(scalar) == "number", typeName .. " division expects a scalar")
        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, a[componentName] / scalar)
        end
        return methods.new(table.unpack(values))
    end

    function metatable.__eq(a, b)
        for _, componentName in ipairs(componentNames) do
            if a[componentName] ~= b[componentName] then
                return false
            end
        end
        return true
    end

    function metatable.__tostring(value)
        local values = {}
        for _, componentName in ipairs(componentNames) do
            table.insert(values, tostring(value[componentName]))
        end
        return table.concat(values, ", ")
    end

    function methods.new(...)
        local arguments = pack(...)
        local value = {
            __bloxenvType = typeName,
        }
        for index, componentName in ipairs(componentNames) do
            value[componentName] = arguments[index] or 0
        end
        return setmetatable(value, metatable)
    end

    methods.zero = methods.new()
    return methods
end

local Vector2 = createVectorType("Vector2", { "X", "Y" })
local Vector3 = createVectorType("Vector3", { "X", "Y", "Z" })

env.Vector2 = Vector2
env.Vector3 = Vector3

local Color3 = {}
local color3Metatable = {}

function Color3.new(r, g, b)
    return setmetatable({
        __bloxenvType = "Color3",
        R = r or 0,
        G = g or 0,
        B = b or 0,
    }, color3Metatable)
end

function Color3.fromRGB(r, g, b)
    return Color3.new(r / 255, g / 255, b / 255)
end

function color3Metatable.__tostring(value)
    return string.format("%g, %g, %g", value.R, value.G, value.B)
end

env.Color3 = Color3

-- Lazy Enum implementation --------------------------------------------------

local enumTypes = {}
local enumMetatable = {}
local enumTypeMetatable = {}
local enumItemMetatable = {}

function enumMetatable.__index(_, enumName)
    if not enumTypes[enumName] then
        enumTypes[enumName] = setmetatable({
            __bloxenvType = "Enum",
            Name = enumName,
            _items = {},
        }, enumTypeMetatable)
    end
    return enumTypes[enumName]
end

function enumTypeMetatable.__index(enumType, itemName)
    local items = rawget(enumType, "_items")
    if not items[itemName] then
        items[itemName] = setmetatable({
            __bloxenvType = "EnumItem",
            Name = itemName,
            EnumType = enumType,
            Value = 0,
        }, enumItemMetatable)
    end
    return items[itemName]
end

function enumTypeMetatable.__tostring(enumType)
    return "Enum." .. enumType.Name
end

function enumItemMetatable.__tostring(enumItem)
    return string.format("Enum.%s.%s", enumItem.EnumType.Name, enumItem.Name)
end

env.Enum = setmetatable({}, enumMetatable)

-- DataModel and default services --------------------------------------------

local game = createInstance("DataModel")
game.Name = "game"
game.PlaceId = 0
game.GameId = 0
game.JobId = "bloxenv-local"
game.PrivateServerId = ""
game.PrivateServerOwnerId = 0
game.Loaded = Signal.new()

local services = {}

local function registerService(name, className)
    local service = createInstance(className or name)
    service.Name = name
    service.Parent = game
    services[name] = service
    return service
end

local Workspace = registerService("Workspace", "Workspace")
local Players = registerService("Players", "Players")
local ReplicatedStorage = registerService("ReplicatedStorage", "ReplicatedStorage")
local ServerStorage = registerService("ServerStorage", "ServerStorage")
local RunService = registerService("RunService", "RunService")
local HttpService = registerService("HttpService", "HttpService")
local CollectionService = registerService("CollectionService", "CollectionService")

function game:GetService(name)
    assert(type(name) == "string", "DataModel:GetService expects a service name")

    local existing = services[name]
    if existing then
        return existing
    end

    if BloxEnv.config.strict or __BLOXENV_STRICT then
        error("BloxEnv does not implement service '" .. name .. "'", 2)
    end

    local generated = registerService(name, name)
    warn("BloxEnv created a generic mock for unsupported service " .. name)
    return generated
end

function game:FindService(name)
    return services[name]
end

function game:IsLoaded()
    return true
end

Players.PlayerAdded = Signal.new()
Players.PlayerRemoving = Signal.new()
Players.LocalPlayer = nil

function Players:GetPlayers()
    local result = {}
    for _, child in ipairs(self:GetChildren()) do
        if child:IsA("Player") then
            table.insert(result, child)
        end
    end
    return result
end

function Players:GetPlayerByUserId(userId)
    for _, player in ipairs(self:GetPlayers()) do
        if player.UserId == userId then
            return player
        end
    end
    return nil
end

function Players:GetPlayerFromCharacter(character)
    for _, player in ipairs(self:GetPlayers()) do
        if player.Character == character then
            return player
        end
    end
    return nil
end

RunService.Heartbeat = Signal.new()
RunService.Stepped = Signal.new()
RunService.RenderStepped = Signal.new()
RunService.PreSimulation = Signal.new()
RunService.PostSimulation = Signal.new()
RunService.Heartbeat._bloxenvInterval = 1 / 60
RunService.Stepped._bloxenvInterval = 1 / 60
RunService.RenderStepped._bloxenvInterval = 1 / 60
RunService.PreSimulation._bloxenvInterval = 1 / 60
RunService.PostSimulation._bloxenvInterval = 1 / 60
RunService._context = "server"

function RunService:IsServer()
    return self._context == "server"
end

function RunService:IsClient()
    return self._context == "client"
end

function RunService:IsStudio()
    return self._context == "studio"
end

function RunService:IsRunning()
    return true
end

scheduler.onAdvance = function(deltaTime)
    RunService.Stepped:Fire(scheduler.now, deltaTime)
    RunService.PreSimulation:Fire(deltaTime)
    RunService.PostSimulation:Fire(deltaTime)
    RunService.Heartbeat:Fire(deltaTime)
    if RunService:IsClient() or RunService:IsStudio() then
        RunService.RenderStepped:Fire(deltaTime)
    end
end

function HttpService:GenerateGUID(wrapInCurlyBraces)
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    local guid = string.gsub(template, "[xy]", function(character)
        local value = math.random(0, 15)
        if character == "y" then
            value = (value % 4) + 8
        end
        return string.format("%x", value)
    end)

    if wrapInCurlyBraces then
        return "{" .. guid .. "}"
    end
    return guid
end

function HttpService:JSONEncode(_value)
    error("HttpService:JSONEncode is not implemented yet. Override it in bloxenv.config.luau.", 2)
end

function HttpService:JSONDecode(_value)
    error("HttpService:JSONDecode is not implemented yet. Override it in bloxenv.config.luau.", 2)
end

local collectionTags = setmetatable({}, { __mode = "k" })
local tagAddedSignals = {}
local tagRemovedSignals = {}

function CollectionService:AddTag(instance, tag)
    assert(isInstance(instance), "CollectionService:AddTag expects an Instance")
    collectionTags[instance] = collectionTags[instance] or {}
    if not collectionTags[instance][tag] then
        collectionTags[instance][tag] = true
        if tagAddedSignals[tag] then
            tagAddedSignals[tag]:Fire(instance)
        end
    end
end

function CollectionService:RemoveTag(instance, tag)
    local tags = collectionTags[instance]
    if tags and tags[tag] then
        tags[tag] = nil
        if tagRemovedSignals[tag] then
            tagRemovedSignals[tag]:Fire(instance)
        end
    end
end

function CollectionService:HasTag(instance, tag)
    local tags = collectionTags[instance]
    return tags ~= nil and tags[tag] == true
end

function CollectionService:GetTagged(tag)
    local result = {}
    for instance, tags in pairs(collectionTags) do
        if tags[tag] then
            table.insert(result, instance)
        end
    end
    return result
end

function CollectionService:GetInstanceAddedSignal(tag)
    tagAddedSignals[tag] = tagAddedSignals[tag] or Signal.new()
    return tagAddedSignals[tag]
end

function CollectionService:GetInstanceRemovedSignal(tag)
    tagRemovedSignals[tag] = tagRemovedSignals[tag] or Signal.new()
    return tagRemovedSignals[tag]
end

env.game = game
env.workspace = Workspace

-- typeof/warn wrappers -------------------------------------------------------

env.typeof = function(value)
    if type(value) == "table" then
        local customType = rawget(value, "__bloxenvType")
        if customType then
            return customType
        end
    end
    return hostTypeof(value)
end

if env.warn == nil then
    env.warn = function(...)
        print("[BloxEnv warning]", ...)
    end
end

-- Configuration application -------------------------------------------------

local reservedDescriptorKeys = {
    ClassName = true,
    Name = true,
    Children = true,
    Properties = true,
}

local applyPatch

local function createFromDescriptor(defaultName, descriptor)
    if isInstance(descriptor) then
        if defaultName then
            descriptor.Name = defaultName
        end
        return descriptor
    end

    local className = descriptor.ClassName or "Folder"
    local object = createInstance(className)
    object.Name = descriptor.Name or defaultName or className

    if descriptor.Properties then
        applyPatch(object, descriptor.Properties)
    end

    for key, value in pairs(descriptor) do
        if not reservedDescriptorKeys[key] then
            if type(value) == "table" and value.ClassName then
                local nested = createFromDescriptor(key, value)
                nested.Parent = object
            else
                object[key] = value
            end
        end
    end

    if descriptor.Children then
        applyPatch(object, { Children = descriptor.Children })
    end

    return object
end

applyPatch = function(target, patch)
    for key, value in pairs(patch) do
        if key ~= "Children" then
            if type(value) == "table" and value.ClassName then
                target[key] = createFromDescriptor(key, value)
            else
                local current = target[key]
                if type(current) == "table"
                    and type(value) == "table"
                    and not isInstance(value)
                    and rawget(value, "__bloxenvType") == nil
                then
                    applyPatch(current, value)
                else
                    target[key] = value
                end
            end
        end
    end

    local children = patch.Children
    if children and isInstance(target) then
        for name, descriptor in pairs(children) do
            local defaultName = if type(name) == "string" then name else nil
            local child = createFromDescriptor(defaultName, descriptor)
            child.Parent = target
        end
    end
end

local function splitPath(path)
    local result = {}
    for segment in string.gmatch(path, "[^%.]+") do
        table.insert(result, segment)
    end
    return result
end

function BloxEnv.resolve(path)
    assert(type(path) == "string", "BloxEnv.resolve expects a dot-separated path")

    local segments = splitPath(path)
    local current
    local first = table.remove(segments, 1)

    if first == "game" then
        current = game
    elseif first == "workspace" then
        current = Workspace
    elseif first == "BloxEnv" then
        current = BloxEnv
    else
        current = env[first]
    end

    for _, segment in ipairs(segments) do
        if current == nil then
            return nil
        end
        current = current[segment]
    end

    return current
end

function BloxEnv.set(path, value)
    assert(type(path) == "string", "BloxEnv.set expects a dot-separated path")

    local segments = splitPath(path)
    assert(#segments >= 2, "BloxEnv.set path must include an object and property")

    local propertyName = table.remove(segments)
    local parent = BloxEnv.resolve(table.concat(segments, "."))
    assert(parent ~= nil, "BloxEnv.set could not resolve " .. table.concat(segments, "."))
    parent[propertyName] = value
end

function BloxEnv.addPlayer(properties, makeLocalPlayer)
    local player = createInstance("Player")
    player.Name = "Player"
    player.DisplayName = player.Name
    player.UserId = 0
    applyPatch(player, properties or {})
    player.Parent = Players

    if makeLocalPlayer then
        Players.LocalPlayer = player
    end

    Players.PlayerAdded:Fire(player)
    return player
end

function BloxEnv.removePlayer(player)
    if player.Parent == Players then
        Players.PlayerRemoving:Fire(player)
        if Players.LocalPlayer == player then
            Players.LocalPlayer = nil
        end
        player:Destroy()
    end
end

function BloxEnv.createInstance(className, properties, parent)
    local object = createInstance(className)
    applyPatch(object, properties or {})
    if parent then
        object.Parent = parent
    end
    return object
end

function BloxEnv._applyConfig(config)
    assert(type(config) == "table", "bloxenv.config.luau must return a table")
    BloxEnv.config = config

    if config.scheduler and config.scheduler.maxSteps then
        scheduler.maxSteps = config.scheduler.maxSteps
    end

    if config.context then
        assert(
            config.context == "server" or config.context == "client" or config.context == "studio",
            "config.context must be 'server', 'client', or 'studio'"
        )
        RunService._context = config.context
    end

    if config.game then
        applyPatch(game, config.game)
    end

    if config.services then
        for serviceName, patch in pairs(config.services) do
            -- A service explicitly declared by the config is supported by
            -- definition, even when strict mode is enabled.
            local service = services[serviceName]
            if not service then
                service = registerService(serviceName, serviceName)
            end
            applyPatch(service, patch)
        end
    end

    if Players.LocalPlayer and isInstance(Players.LocalPlayer) and Players.LocalPlayer.Parent == nil then
        Players.LocalPlayer.Parent = Players
    end

    if config.overrides then
        for path, value in pairs(config.overrides) do
            BloxEnv.set(path, value)
        end
    end

    if config.globals then
        for name, value in pairs(config.globals) do
            env[name] = value
        end
    end
end

local function basename(path)
    local normalized = string.gsub(path, "\\", "/")
    return string.match(normalized, "([^/]+)$") or normalized
end

local function nameWithoutExtension(path)
    local name = basename(path)
    name = string.gsub(name, "%.server%.luau$", "")
    name = string.gsub(name, "%.client%.luau$", "")
    name = string.gsub(name, "%.luau$", "")
    name = string.gsub(name, "%.lua$", "")
    return name
end

local function createScriptEnvironment(sourceContainer)
    return setmetatable({
        script = sourceContainer,
    }, {
        __index = env,
    })
end

function BloxEnv._bindChunk(chunk, path, className)
    assert(type(chunk) == "function", "BloxEnv._bindChunk expected a compiled chunk")

    local sourceContainer = createInstance(className or "Script")
    sourceContainer.Name = nameWithoutExtension(path)
    sourceContainer.SourcePath = path

    setfenv(chunk, createScriptEnvironment(sourceContainer))
    return chunk
end

-- Module loading -------------------------------------------------------------

local moduleCache = {}
local loadingModules = {}

local function requireModule(request)
    local requestedPath
    local moduleScript

    if type(request) == "string" then
        requestedPath = request
    elseif isInstance(request) and request:IsA("ModuleScript") then
        requestedPath = request.SourcePath
        moduleScript = request
    else
        error("BloxEnv require expects a path string or ModuleScript with SourcePath", 2)
    end

    assert(type(requestedPath) == "string" and requestedPath ~= "", "ModuleScript.SourcePath must be set")

    local callerEnvironment = getfenv(2)
    local callerScript = callerEnvironment and callerEnvironment.script
    local basePath = if callerScript and callerScript.SourcePath then callerScript.SourcePath else __BLOXENV_TARGET_PATH
    local chunk, canonicalPath = _bloxenv_loadmodule(requestedPath, basePath)

    if moduleCache[canonicalPath] ~= nil then
        return moduleCache[canonicalPath]
    end

    if loadingModules[canonicalPath] then
        error("Circular module dependency detected while requiring " .. canonicalPath, 2)
    end

    loadingModules[canonicalPath] = true

    if not moduleScript then
        moduleScript = createInstance("ModuleScript")
        moduleScript.Name = nameWithoutExtension(canonicalPath)
    end

    -- Always store the canonical path after resolution. This makes nested
    -- relative require() calls work even when the config used a relative
    -- ModuleScript.SourcePath.
    moduleScript.SourcePath = canonicalPath
    setfenv(chunk, createScriptEnvironment(moduleScript))

    local ok, result = pcall(chunk)
    loadingModules[canonicalPath] = nil

    if not ok then
        error(result, 2)
    end

    if result == nil then
        error("Module " .. canonicalPath .. " returned nil; BloxEnv modules must return a value", 2)
    end

    moduleCache[canonicalPath] = result
    return result
end

env.require = requireModule

function BloxEnv.clearModuleCache()
    table.clear(moduleCache)
    table.clear(loadingModules)
end

function BloxEnv._execute(chunk)
    assert(type(chunk) == "function", "BloxEnv._execute expected a compiled target chunk")

    local targetEnvironment = getfenv(chunk)
    if BloxEnv.config.script and targetEnvironment and targetEnvironment.script then
        applyPatch(targetEnvironment.script, BloxEnv.config.script)
    end

    if type(BloxEnv.config.beforeRun) == "function" then
        BloxEnv.config.beforeRun(BloxEnv)
    end

    local targetThread = taskLibrary.spawn(chunk)
    BloxEnv.runUntilIdle()

    if coroutine.status(targetThread) ~= "dead" then
        error(
            "BloxEnv scheduler became idle while the target script was still waiting. "
                .. "Schedule an event/task that resumes it, or add a timeout.",
            2
        )
    end

    if type(BloxEnv.config.afterRun) == "function" then
        BloxEnv.config.afterRun(BloxEnv)
    end
end
