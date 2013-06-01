local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

function bound_as_thread(obj, method)
   local fn = function(go, comp)
      while true do
         coroutine.yield()
         obj[method](obj)
      end
   end
   return util.thread(fn)
end

local DynO = oo.class(oo.Object)

function DynO:init()
   self.go = world:create_go()
   self.go:body_type(constant.DYNAMIC)
   self.scripted = self.go:add_component('CScripted', {update_thread=bound_as_thread(self, 'update')})
end

function DynO:terminate()
   self.go:delete_me(1)
end

local Bullet = oo.class(DynO)

function Bullet:init(pos, vel)
   DynO.init(self)

   self.go:pos(pos)
   self.testbox = self.go:add_component('CTestDisplay', {w=32,h=32})
   self.tgt_vel = vel
end

function Bullet:update()
   local go = self.go
   local pos = go:pos()
   local vel = vector.new(go:vel())

   local dv = self.tgt_vel - vel
   self.go:apply_impulse(dv * go:mass())

   -- kill on screen exit
   if pos[1] > screen_width or pos[1] < 0 or pos[2] > screen_height or pos[2] < 0 then
      self:terminate()
   end
end

local Player = oo.class(DynO)

function Player:init()
   DynO.init(self)

   self.testbox = self.go:add_component('CTestDisplay', {w=32,h=32})
   self.max_slide_rate = 1000
   self.delay_factor = 0.98
   self.shot_speed = 2000
end

function Player:update()
   local input = util.input_state()
   local go = self.go
   local pos = go:pos()
   local vel = vector.new(go:vel())

   local xx = input.leftright * self.max_slide_rate
   local yy = input.updown * self.max_slide_rate

   local desired_dv = (vector.new({xx,yy}) - vel) * self.delay_factor

   local imp = desired_dv * go:mass()
   go:apply_impulse(imp)

   if input.action1 then
      Bullet(pos, vector.new({0, self.shot_speed}))
   end

   -- fix position
   if pos[1] > screen_width then
      pos[1] = screen_width
   elseif pos[1] < 0 then
      pos[1] = 0
   end
   if pos[2] > screen_height then
      pos[2] = screen_height
   elseif pos[2] < 0 then
      pos[2] = 0
   end
   go:pos(pos)
end

function level_init()
   util.install_basic_keymap()
   world:gravity({0,0})
   local player = Player()
end
