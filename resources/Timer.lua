local oo = require 'oo'
local util = require 'util'
local constant = require 'constant'

local Timer = oo.class(oo.Object)
Timer.timers = {}

function Timer.register()
   local thread = function(go, comp)
      while true do
         coroutine.yield()
         for ii, timer in ipairs(Timer.timers) do
            timer:evaluate()
         end
      end
   end
   stage:add_component('CScripted', {message_thread=util.thread(thread)})
end

function Timer:init()
   self.timer = nil
   self.msg = constant.NEXT_EPHEMERAL_MESSAGE()
   table.insert(Timer.timers, self)
end

function Timer:maybe_set(timeout, fn)
   if not self.timer then
      self.timer = stage:add_component('CTimer',
                                       {kind=self.msg,
                                        time_remaining=timeout})
      self.fn = fn
   end
end

function Timer:reset(timeout, fn)
   self.fn = fn
   if not self.timer then
      self.timer = stage:add_component('CTimer',
                                       {kind=self.msg,
                                        time_remaining=timeout})
   else
      self.timer:delete_me(0)
      self.timer:time_remaining(timeout)
   end
end

function Timer:evaluate()
   if stage:has_message(self.msg) then
      self.fn()
      if self.timer:delete_me() == 1 then
         self.timer = nil
         self.fn = nil
      end
   end
end

return Timer
