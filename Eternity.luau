--!native
--!optimize 2
--!strict

--[[

	      ..      .         .....                ..      .          ..      ...          ...     ...         .....     .      .....                             
	   x88f` `..x88. .>  .H8888888h.  ~-.     x88f` `..x88. .>   :~"8888x :"%888x     .=*8888n.."%888:     .d88888Neu. 'L  .H8888888h.  ~-.     .xnnx.  .xx.    
	 :8888   xf`*8888%   888888888888x  `>  :8888   xf`*8888%   8    8888Xf  8888>   X    ?8888f '8888     F""""*8888888F  888888888888x  `>  .f``"888X< `888.  
	:8888f .888  `"`    X~     `?888888hx~ :8888f .888  `"`    X88x. ?8888k  8888X   88x. '8888X  8888>   *      `"*88*"  X~     `?888888hx~  8L   8888X  8888  
	88888' X8888. >"8x  '      x8.^"*88*"  88888' X8888. >"8x  '8888L'8888X  '%88X  '8888k 8888X  '"*8h.   -....    ue=:. '      x8.^"*88*"  X88h. `8888  X888k 
	88888  ?88888< 888>  `-:- X8888x       88888  ?88888< 888>  "888X 8888X:xnHH(``  "8888 X888X .xH8             :88N  `  `-:- X8888x       '8888 '8888  X8888 
	88888   "88888 "8%        488888>      88888   "88888 "8%     ?8~ 8888X X8888      `8" X888!:888X             9888L         488888>       `*88>'8888  X8888 
	88888 '  `8888>         .. `"88*       88888 '  `8888>      -~`   8888> X8888     =~`  X888 X888X      uzu.   `8888L      .. `"88*          `! X888~  X8888 
	`8888> %  X88!        x88888nX"      . `8888> %  X88!       :H8x  8888  X8888      :h. X8*` !888X    ,""888i   ?8888    x88888nX"      .   -`  X*"    X8888 
	 `888X  `~""`   :    !"*8888888n..  :   `888X  `~""`   :    8888> 888~  X8888     X888xX"   '8888..: 4  9888L   %888>  !"*8888888n..  :     xH88hx  . X8888 
	   "88k.      .~    '    "*88888888*      "88k.      .~     48"` '8*~   `8888!` :~`888f     '*888*"  '  '8888   '88%  '    "*88888888*    .*"*88888~  X888X 
	     `""*==~~`              ^"***"`         `""*==~~`        ^-==""      `""        ""        `"`         "*8Nu.z*"           ^"***"`     `    "8%    X888> 
	                                                                                                                                             .x..     888f  
	                                                                                                                                            88888    :88f   
	                                                                                                                                            "88*"  .x8*~    
                                                                                                                                            
    A lightweight, type-safe Promise/Async library written by @stlxvy
--]]

export type PromiseStatus = "pending" | "resolved" | "rejected"

export type CallbackPair<T> = {
	on_resolve: ((T) -> ())?,
	on_reject: ((any) -> ())?,
}

export type Promise<T> = typeof(setmetatable(
	{} :: {
		_state: PromiseStatus,
		_value: any,
		_callbacks: {CallbackPair<T>}?,
	},
	{} :: {
		__index: {
			and_then: (self: any, on_resolve: ((T) -> any)?, on_reject: ((any) -> any)?) -> any,
			catch: (self: any, on_reject: (any) -> any) -> any,
			finally: (self: any, on_finally: () -> ()) -> any,
		}
	}
	)
)

local STATE_PENDING: PromiseStatus = "pending"
local STATE_RESOLVED: PromiseStatus = "resolved"
local STATE_REJECTED: PromiseStatus = "rejected"

local Promise = {}
local promise_mt = {__index = Promise}

--[[
    Takes a resolver function that receives resolve/reject callbacks
    The executor runs immediately and synchronously to keep predictable semantics
]]
local function create_promise<T>(executor: (resolve: (T) -> (), reject: (any) -> ()) -> ()): Promise<T>
	local self = {
		_state = STATE_PENDING :: PromiseStatus,
		_value = nil :: any,
		_callbacks = {} :: {CallbackPair<T>},
	}

	setmetatable(self, promise_mt)

	-- Single-shot resolve/reject to prevent state corruption
	local settled = false

	local function resolve(value: T)
		if settled then return end
		settled = true

		self._state = STATE_RESOLVED
		self._value = value

		-- Execute all queued callbacks immediately to maintain execution order
		local callbacks = self._callbacks
		if callbacks then
			for _, callback_pair in callbacks do
				if callback_pair.on_resolve then
					task.spawn(callback_pair.on_resolve, value)
				end
			end
			(self :: any)._callbacks = nil -- Release callback references
		end
	end

	local function reject(reason: any)
		if settled then return end
		settled = true

		self._state = STATE_REJECTED
		self._value = reason

		local callbacks = self._callbacks
		if callbacks then
			for _, callback_pair in callbacks do
				if callback_pair.on_reject then
					task.spawn(callback_pair.on_reject, reason)
				end
			end
			(self :: any)._callbacks = nil
		end
	end

	local success = pcall(function()
		executor(resolve, reject)
	end)

	if not success then
		reject("Executor threw an error")
	end

	return self :: any
end

--[[
    Chaining mechanism, creates a new promise that resolves/rejects based on callback results
    Handles both value returns and promise returns (flattening nested promises)
]]
local function and_then(self: any, on_resolve: ((any) -> any)?, on_reject: ((any) -> any)?): any
	return create_promise(function(resolve, reject)
		local function handle_resolve(value: any)
			if not on_resolve then
				resolve(value)
				return
			end

			local success, result = pcall(on_resolve, value)
			if not success then
				reject(result)
				return
			end

			-- Handle promise chaining. If result is a promise: wait for it
			if type(result) == "table" and getmetatable(result) == promise_mt then
				result:and_then(resolve, reject)
			else
				resolve(result)
			end
		end

		local function handle_reject(reason: any)
			if not on_reject then
				reject(reason)
				return
			end

			local success, result = pcall(on_reject, reason)
			if not success then
				reject(result)
				return
			end

			if type(result) == "table" and getmetatable(result) == promise_mt then
				result:and_then(resolve, reject)
			else
				resolve(result)
			end
		end

		-- If already settled, execute immediately
		if self._state == STATE_RESOLVED then
			handle_resolve(self._value)
		elseif self._state == STATE_REJECTED then
			handle_reject(self._value)
		else
			local callbacks = self._callbacks
			if callbacks then
				table.insert(callbacks, {
					on_resolve = handle_resolve,
					on_reject = handle_reject,
				})
			end
		end
	end)
end

Promise.and_then = and_then

local function catch(self: any, on_reject: (any) -> any): any
	return and_then(self, nil, on_reject)
end

Promise.catch = catch

local function finally(self: any, on_finally: () -> ()): any
	return and_then(
		self,
		function(value)
			on_finally()
			return value
		end,
		function(reason)
			on_finally()
			error(reason, 0)
		end
	)
end

Promise.finally = finally

--[[
    Static constructors for common promise patterns
]]
local function resolve<T>(value: T): Promise<T>
	local self = {
		_state = STATE_RESOLVED :: PromiseStatus,
		_value = value :: any,
		_callbacks = nil :: {CallbackPair<T>}?,
	}
	setmetatable(self, promise_mt)
	return self :: any
end

local function reject<T>(reason: any): Promise<T>
	local self = {
		_state = STATE_REJECTED :: PromiseStatus,
		_value = reason :: any,
		_callbacks = nil :: {CallbackPair<T>}?,
	}
	setmetatable(self, promise_mt)
	return self :: any
end

--[[
    Combinators operate on multiple promises efficiently
    These minimize the overhead by avoiding any intermediate promise creation (where possible)
]]
local function all<T>(promises: {Promise<T>}): Promise<{T}>
	return create_promise(function(resolve, reject)
		local results: {T} = {}
		local remaining = #promises

		if remaining == 0 then
			resolve(results)
			return
		end

		for i, promise in promises do
			promise:and_then(
				function(value)
					results[i] = value
					remaining -= 1
					if remaining == 0 then
						resolve(results)
					end
					return nil
				end,
				function(reason)
					reject(reason)
					return nil
				end
			)
		end
	end)
end

local function race<T>(promises: {Promise<T>}): Promise<T>
	return create_promise(function(resolve, reject)
		for _, promise in promises do
			promise:and_then(
				function(value)
					resolve(value)
					return nil
				end,
				function(reason)
					reject(reason)
					return nil
				end
			)
		end
	end)
end

local function any<T>(promises: {Promise<T>}): Promise<T>
	return create_promise(function(resolve, reject)
		local errors: {any} = {}
		local remaining = #promises

		if remaining == 0 then
			reject("No promises provided")
			return
		end

		for i, promise in promises do
			promise:and_then(
				function(value)
					resolve(value)
					return nil
				end,
				function(reason)
					errors[i] = reason
					remaining -= 1
					if remaining == 0 then
						reject(errors)
					end
					return nil
				end
			)
		end
	end)
end

--[[
    Utility functions for common async patterns
]]
local function delay(seconds: number): Promise<number>
	return create_promise(function(resolve, _reject)
		task.delay(seconds, resolve, seconds)
	end)
end

local function from_callback<T>(callback: ((callback: (T) -> ()) -> ())): Promise<T>
	return create_promise(function(resolve, _reject)
		callback(resolve)
	end)
end

return {
	new = create_promise,
	resolve = resolve,
	reject = reject,
	all = all,
	race = race,
	any = any,
	delay = delay,
	from_callback = from_callback,
}
