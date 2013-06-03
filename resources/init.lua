local oo = require 'oo'
local util = require 'util'
local Timer = require 'Timer'
local vector = require 'vector'
local constant = require 'constant'
local Registry = require 'Registry'

local reg = Registry()
local max_enemies = 50

local DynO
local SimpletonBrain
local DragBrain
local BaseEnemy
local Formation
local Spawner
local Bullet
local Gun
local Goodie
local Player

local ATLAS = 'resources/default'

DynO = oo.class(oo.Object)
function DynO:init(pos)
   self.go = world:create_go()
   reg:register(self.go, self)

   self.go:pos(pos)
   self.go:body_type(constant.DYNAMIC)
   self.scripted = self.go:add_component('CScripted', {update_thread=util.fthread(self:bind('update')),
                                                       message_thread=util.fthread(self:bind('message'))})
end

function DynO:message()
   local go = self.go
   local msgs = { go:has_message(constant.COLLIDING) }
   for ii, msg in ipairs(msgs) do
      local obj = reg:find(msg.source)
      if obj then
         self:colliding_with(obj)
      end
   end
end

function DynO:colliding_with(obj)
   -- pass
end

function DynO:add_sensor(parms)
   if not self.sensors then
      self.sensors = {}
   end
   table.insert(self.sensors, self.go:add_component('CSensor', parms))
end

function DynO:add_collider(parms)
   if not self.colliders then
      self.colliders = {}
   end
   table.insert(self.colliders, self.go:add_component('CCollidable', parms))
end

function DynO:terminate()
   self.go:delete_me(1)
   reg:unregister(self.go)
end

local function terminate_if_offscreen(self)
   local fuzz = 128
   local pos = self.go:pos()

   -- kill on screen exit
   if pos[1] > screen_width + fuzz or pos[1] < -fuzz or pos[2] > screen_height + fuzz or pos[2] < -fuzz then
      self:terminate()
   end
end

SimpletonBrain = oo.class(oo.Object)

function SimpletonBrain:init(tgt_vel, max_force)
   self.tgt_vel = tgt_vel
   self.max_force = max_force or 10
end

function SimpletonBrain:update(obj)
   local go = obj.go
   local pos = go:pos()
   local vel = vector.new(go:vel())

   local dv = self.tgt_vel - vel
   if dv:length() > self.max_force then
      dv = dv:norm() * self.max_force
   end
   go:apply_force(dv)
end

DragBrain = oo.class(oo.Object)

function DragBrain:init(drag_factor)
   self.drag_factor = drag_factor or 10
end

function DragBrain:update(obj)
   local vel = vector.new(obj.go:vel())
   if vel:length() > 1 then
      obj.go:apply_force(vel * (-self.drag_factor))
   end
end

BaseEnemy = oo.class(DynO)
BaseEnemy.active_count = 0

function BaseEnemy:init(pos, brain)
   DynO.init(self, pos)
   self.brain = brain or DragBrain()
   BaseEnemy.active_count = BaseEnemy.active_count + 1
end

function BaseEnemy:terminate()
   DynO.terminate(self)
   BaseEnemy.active_count = BaseEnemy.active_count - 1
end

function BaseEnemy:update()
   self.brain:update(self)
   terminate_if_offscreen(self)
end

function create_enemy_type(entry_name, c, d)
   local Enemy = oo.class(BaseEnemy)
   local _art = world:atlas_entry(ATLAS, entry_name)
   local w2 = _art.w/2
   local h2 = _art.h/2
   local ws = 2/3.0
   local hs = 4/5.0

   local points = {
      {w2,h2*hs}, -- mtr
      {w2*ws,h2},
      {-w2*ws,h2},
      {-w2,h2*hs}, -- tl
      {-w2,-h2*hs}, -- ml
      {-w2*ws, -h2}, -- bl
      {w2*ws, -h2}, -- br
      {w2, -h2*hs}}

   Enemy.init = function(self, pos)
      BaseEnemy.init(self, pos)

      self.testbox = self.go:add_component('CStaticSprite', {entry=_art})
      self:add_collider({fixture={type='poly', points=points, density=d}})
   end
   return Enemy
end

local SmallEnemy = create_enemy_type('small_trash', {1,0,1,1}, 1)
local FatEnemy = create_enemy_type('medium_trash', {1,1,0,1}, 10)
local HugeEnemy = create_enemy_type('large_trash', {1,1,0,0.7}, 30)

Formation = oo.class(oo.Object)

function Formation:init(pos)
   local e = SmallEnemy
   local f = {{0, 0}, {-1,1}, {1,1}, {-2,2}, {2,2}}
   local s = 40

   for ii, offset in ipairs(f) do
      local npos = (vector.new(offset) * s) + pos
      e(npos)
   end
end

local function always_spawn()
   return true
end

Spawner = oo.class(oo.Object)

function Spawner:init(rate, mix, height, should_spawn)
   self.rate = rate
   self.mix = mix
   self.height = height
   self.should_spawn = should_spawn or always_spawn
   self.timer = Timer()
   self:reset()
end

function Spawner:reset()
   local next_time = util.rand_exponential(self.rate)
   self.timer:reset(next_time, self:bind('spawn'))
end

function Spawner:spawn()
   -- for now, just spawn at the top of the screen
   if self.should_spawn() then
      local e = util.rand_choice(self.mix)
      e({util.rand_between(0,screen_width), self.height})
   end
   self:reset()
end

Bullet = oo.class(DynO)

function Bullet:init(pos, opts)
   DynO.init(self, pos)

   local _art = world:atlas_entry(ATLAS, 'bubble1')
   self.brain = opts.brain
   self.testbox = self.go:add_component('CStaticSprite', {entry=_art})
   self:add_collider({fixture={type='rect', w=8, h=8, density=opts.density}})
   self.timer = Timer(self.go)
   self.timer:reset(opts.lifetime or 20, self:bind('terminate'))
end

function Bullet:update()
   self.brain:update(self)
   terminate_if_offscreen(self)
end

Gun = oo.class(oo.Object)

function Gun:init(bullet_kind)
   self.bullet_kind = bullet_kind or Bullet
   self.bubble_force = 100
   self.bullet_density = 1
   self.make_bullet_brain = function()
      return SimpletonBrain({0, 1000}, self.bubble_force)
   end
end

function Gun:fire(owner)
   self.bullet_kind(owner.go:pos(),
                    {density=self.bullet_density,
                     brain=self.make_bullet_brain()})
end

local function effect_add_force(player)
   local gun = player.gun
   gun.bubble_force = gun.bubble_force + 100
end

Goodie = oo.class(DynO)

function Goodie:init(pos, brain, effect)
   DynO.init(self, pos)

   local _art = world:atlas_entry(ATLAS, 'powerup1')
   self.brain = brain or SimpletonBrain({0,-500})
   self.testbox = self.go:add_component('CStaticSprite', {entry=_art})
   self.effect = effect or effect_add_force
   self:add_sensor({fixture={type='rect',w=16,h=16,sensor=true}})
end

function Goodie:apply_to(player)
   self.effect(player)
   self:terminate()
end

function Goodie:update()
   self.brain:update(self)
   terminate_if_offscreen(self)
end

function Goodie:colliding_with(obj)
   if obj:is_a(Player) then
      self:apply_to(obj)
   end
end

function HugeEnemy:terminate()
   BaseEnemy.terminate(self)

   local pos = self.go:pos()
   if pos[2] > screen_height then
      -- spawn a goodie when we disolve
      Goodie({pos[1], screen_height})
   end
end

Player = oo.class(DynO)

function Player:init(pos)
   DynO.init(self, pos)

   local _art = world:atlas_entry(ATLAS, 'player')
   self._right_art = _art
   self._left_art = world:atlas_entry(ATLAS, '/xplayer')

   self.sprite = self.go:add_component('CStaticSprite', {entry=self._right_art})
   self.max_slide_rate = 700
   self.delay_factor = 0.70
   self.gun = Gun()
   self:add_collider({fixture={type='rect',w=_art.w,h=_art.h,density=50}})
end

function Player:update()
   local input = util.input_state()
   local go = self.go
   local pos = go:pos()
   local vel = vector.new(go:vel())

   local xx = input.leftright * self.max_slide_rate
   if xx > 0 then
      self.sprite:entry(self._right_art)
   elseif xx < 0 then
      self.sprite:entry(self._left_art)
   end

   local yy = 0 --input.updown * self.max_slide_rate

   local desired_dv = (vector.new({xx,yy}) - vel) * self.delay_factor

   local imp = desired_dv * go:mass()
   go:apply_impulse({imp[1], 0})

   if input.action1 then
      self.gun:fire(self)
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

function add_ground()
   local h = 32
   local w = screen_width;
   local offset = {w/2, h/2}
   stage:add_component('CTestDisplay', {w=w, h=h, offset=offset, color={0.2, 0.7, 0.2, 1}})
   stage:add_component('CCollidable', {fixture={type='rect',w=w,h=h,center=offset}})
end

local czor = world:create_object('Compositor')

function black_background()
   czor:clear_with_color(util.rgba(73,150,232,255))
end

function enemy_limited_spawning()
   return BaseEnemy.active_count <= max_enemies
end

function level_init()
   util.install_basic_keymap()

   world:gravity({0,-100})
   local player = Player({screen_width/2, 32})
   local spawn_list = {SmallEnemy, SmallEnemy, SmallEnemy, FatEnemy, HugeEnemy, Formation}
   local spawner = Spawner(1, spawn_list, screen_height + 64, enemy_limited_spawning)
   add_ground()

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(black_background))
end
