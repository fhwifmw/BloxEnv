local inner = require("./Inner")

return function()
    return script.Name, inner.scriptName
end
