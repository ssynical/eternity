# eternity
Ultra-lightweight, type-safe Promise library for Roblox Luau.

----

## Features

Zero-cost abstractions with direct state management, minimal allocations, and predictable performance. Includes all standard Promise operations: chaining, error handling, and combinators (all, race, any)

## Usage

```lua
local Promise = require(path.to.Eternity)

Promise.new(function(resolve, reject)
    task.delay(1, resolve, "done")
end):and_then(function(value)
    print(value)
    return nil
end)
```

## License

MIT License

----

Made with ❤️ | Last updated: 27/12/2025
