--[[-------------------------------------------------------------------------
	downfall_meta:GetNextParticle()

---------------------------------------------------------------------------]]
local max = math.max

-- Particle emitters
if CLIENT then
	_STORMFOX_PEM = _STORMFOX_PEM or ParticleEmitter(Vector(0,0,0),true)
	_STORMFOX_PEM2d = _STORMFOX_PEM2d or ParticleEmitter(Vector(0,0,0))
	_STORMFOX_PEM:SetNoDraw(true)
	_STORMFOX_PEM2d:SetNoDraw(true)
end

-- Downfall mask
local mask = bit.bor( CONTENTS_SOLID, CONTENTS_MOVEABLE, CONTENTS_MONSTER, CONTENTS_WINDOW, CONTENTS_DEBRIS, CONTENTS_HITBOX, CONTENTS_WATER, CONTENTS_SLIME )
local util_TraceHull,bit_band,Vector,IsValid = util.TraceHull,bit.band,Vector,IsValid

StormFox.DownFall = {}

SF_DOWNFALL_HIT_NIL = -1
SF_DOWNFALL_HIT_GROUND = 0
SF_DOWNFALL_HIT_WATER = 1
SF_DOWNFALL_HIT_GLASS = 2

local con = GetConVar("sv_gravity")
-- Returns the gravity
local function GLGravity()
	if con then
		return con:GetInt() / 600
	else -- Err
		return 1
	end
end

--		game.GetTimeScale()

-- Traces
do
	local t = {
		start = Vector(0,0,0),
		endpos = Vector(0,0,0),
		maxs = Vector(1,1,4),
		mins = Vector(-1,-1,0),
		mask = mask
	}
	local function GetViewEntity()
		if SERVER then return end
		return LocalPlayer():GetViewEntity() or LocalPlayer()
	end
	-- Returns a raindrop pos from a sky position. #2 is hittype: -1 = no hit, 0 = ground, 1 = water, 2 = glass.
	local function TraceDown(pos, norm, nRadius, filter)
		nRadius = nRadius or 1
		if not pos or not norm then return end
		t.start = pos
		t.endpos = pos + norm * 262144
		t.maxs.x = nRadius
		t.maxs.y = nRadius
		t.mins.x = -nRadius
		t.mins.y = -nRadius
		t.filter = filter or GetViewEntity()
		local tr = util_TraceHull(t)
		if not tr or not tr.Hit then
			return tr.HitPos, SF_DOWNFALL_HIT_NIL
		elseif bit_band( tr.Contents , CONTENTS_WATER ) == CONTENTS_WATER then
			return tr.HitPos, SF_DOWNFALL_HIT_WATER
		elseif bit_band( tr.Contents , CONTENTS_WINDOW ) == CONTENTS_WINDOW then
			return tr.HitPos, SF_DOWNFALL_HIT_GLASS
		elseif IsValid(tr.Entity) then
			if string.find(tr.Entity:GetModel():lower(), "glass", 1, true) then
				return tr.HitPos, SF_DOWNFALL_HIT_GLASS
			end
		end
		return tr.HitPos, SF_DOWNFALL_HIT_GROUND, tr.HitNormal
	end
	StormFox.DownFall.TraceDown = TraceDown

	-- Returns the skypos. If it didn't find the sky it will return last position as #2
	local function FindSky(vFrom, vNormal, nTries)
		local last
		for i = 1,nTries do
			local t = util.TraceLine( {
				start = vFrom,
				endpos = vFrom + vNormal * 262144,
				mask = MASK_SOLID_BRUSHONLY
			} )
			if t.HitTexture == "TOOLS/TOOLSINVISIBLE" then return end
			if t.HitSky then return t.HitPos end
			if not t.Hit then return nil, last end
			last = t.HitPos
			vFrom = t.HitPos + vNormal
		end
	end
	StormFox.DownFall.FindSky = FindSky
	
	-- Locates the skybox above vFrom and returns a raindrop pos. #2 is hittype: -2 No sky, -1 = no hit/invald, 0 = ground, 1 = water, 2 = glass, #3 is hitnormal
	function StormFox.DownFall.CheckDrop(vFrom, vNorm, nRadius, filter)
		local sky,_ = FindSky(vFrom, -vNorm, 7)
		if not sky then return vFrom, -2 end -- Unable to find a skybox above this position
		return TraceDown(sky + vNorm * nRadius, vNorm * 262144, nRadius, filter)
	end

	-- Does the same as StormFox.DownFall.CheckDrop, but will cache
	local t_cache = {}
	local t_cache_hit = {}
	local c_i = 0
	function StormFox.DownFall.CheckDropCache( ... )
		local pos,n = StormFox.DownFall.CheckDrop( ... )
		if pos and n > -1 then
			c_i = (c_i % 10) + 1
			t_cache[c_i] = pos
			t_cache_hit[c_i] = pos
			return pos,n
		end
		if #t_cache < 1 then return pos,n end
		local n = math.random(1, #t_cache)
		return t_cache[n],t_cache_hit[n]
	end

	local cos,sin,rad = math.cos, math.sin, math.rad
	-- Calculates and locates a downfall-drop infront/nearby of the client.
	-- #1 = Hit Position, #2 hitType, #3 The offset from view, #4 hitNormal
	function StormFox.DownFall.CalculateDrop( nDis, nSize, nTries, vNorm )
		vNorm = vNorm or StormFox.Wind.GetNorm()
		for i = 1, nTries do
			-- Get a random angle
			local d = math.Rand(1,4)

			local deg = math.random(d * 45)
			if math.random() > 0.5 then
				deg = -deg
			end
			-- Calculate the offset
			local view = StormFox.util.GetCalcView()
			local yaw = rad(view.ang.y + deg)
			local offset = view.pos + Vector(cos(yaw),sin(yaw)) * nDis
			local pos, n, hitNorm = StormFox.DownFall.CheckDrop( offset, vNorm, nSize)
			if pos and n > -2 then 
				return pos,n,offset, hitNorm
			end
		end
	end
end

if CLIENT then
	-- Creats a regular particle and returns it
	function StormFox.DownFall.AddParticle( sMaterial, vPos, bUse3D )
		if bUse3D then
			return _STORMFOX_PEM:Add( sMaterial, vPos )
		end
		return _STORMFOX_PEM2d:Add( sMaterial, vPos )
	end
	
	-- Particle Template. Particles "copy" these values when they spawn.
	local pt_meta = {}
	pt_meta.__index = pt_meta
	pt_meta.MetaName = "ParticleTemplate"
	pt_meta.g = 1
	pt_meta.r_H = 400 -- Default render height
	AccessorFunc(pt_meta, "iMat", "Material")
	AccessorFunc(pt_meta, "w", "Width")
	AccessorFunc(pt_meta, "h", "Height")
	AccessorFunc(pt_meta, "c", "Color")
	AccessorFunc(pt_meta, "g", "Speed")
	AccessorFunc(pt_meta, "r_H", "RenderHeight")
	AccessorFunc(pt_meta, "i_G", "IgnoreGravity")
	-- Sets the alpha
	function pt_meta:SetAlpha( nAlpha )
		self.c.a = nAlpha
	end
	function pt_meta:GetAlpha()
		return self.c.a
	end
	function pt_meta:SetSize( nWidth, nHeight )
		self.w = nWidth
		self.h = nHeight
	end
	-- On hit (Overwrite it)
	function pt_meta:OnHit( vPos, vNormal, nHitType )
	end
	function pt_meta:GetNorm()
		return self.vNorm or StormFox.Wind.GetNorm() or Vector(0,0,-1)
	end
	function pt_meta:SetNorm( vNorm )
		self.vNorm = vNorm
	end
	function StormFox.DownFall.CreateTemplate(sMaterial, bBeam)
		local t = {}
		setmetatable(t,pt_meta)
		t:SetMaterial(sMaterial)
		t.c = Color(255,255,255)
		t.bBeam = bBeam or false
		t.w = 32
		t.h = 32
		t.g = 1
		t.r_H = 400
		t.i_G = false
		return t
	end
	-- Particles
	local p_meta = {}
	p_meta.__index = function(self, key)
		return p_meta[key] or self.data[key]
	end
	-- Creates a particle from the template
	function pt_meta:CreateParticle( vEndPos, vNorm, hitType, hitNorm )
		local z_view = StormFox.util.GetCalcView().pos.z
		local t = {}
		t.data = self
		t.vNorm = vNorm
		t.endpos = vEndPos
		t.hitType = hitType or SF_DOWNFALL_HIT_NIL
		t.hitNorm = hitNorm or Vector(0,0,-1)
		setmetatable(t, p_meta)
		local cG = self.g
		if not t:GetIgnoreGravity() then
			cG = self.g * GLGravity()
		end
		local dir_z = math.min(t:GetNorm().z,-0.1) -- Winddir should always be down
		-- Calc the starting position.
		if cG > 0 then -- Start from the sky and down
			local l = z_view + (t.r_H or 200) - t.endpos.z
			t.curlength = l * -dir_z
		elseif cG < 0 then -- Start from ground and up
			local l = math.max(0, z_view - (t.r_H or 200) - t.endpos.z) -- Ground or below renderheight
			t.curlength = l * -dir_z
		end
		return t, (t.r_H or 200) * 2 / math.abs( cG ) -- Secondary is how long we thing it will take for the particle to die. We also want this to be steady.
	end
	-- Calculates the current position of the particle
	function p_meta:CalcPos()
		self.pos = self.endpos - self:GetNorm() * self.curlength
		return self.pos
	end
	-- Returns the current position
	function p_meta:GetPos()
		if self.pos then return self.pos end
		return self:CalcPos()
	end
	-- Sets the alpha of the particle, but won't overwrite template's color.
	function p_meta:SetAlpha( nAlpha )
		if not rawget(self, c) then -- Don't overwrite the template alpha. Create our own color and then modify it.
			self.c = Color(self.c.r, self.c.g, self.c.b, nAlpha)
		else
			self.c.a = nAlpha
		end
	end
	function p_meta:GetHitNormal()
		return self.hitNorm or Vector(0,0,-1)
	end
	-- Renders the particles
	function p_meta:Render()
		local pos = self:GetPos()
		render.SetMaterial(self.iMat)
		if self.bBeam then
			render.DrawBeam(pos - self:GetNorm() * self.h, pos, self.w, 0, 1, self.c)
		else
			render.DrawSprite(pos, self.w, self.h, self.c)
		end
	end
	--[[
		StormFox.DownFall.CreateTemplate(sMaterial, bBeam)
		Creates a template. This particle-data is shared between all other particles that are made from this.
		Do note that you can overwrite this data on each other individual particle as well.

		template:CreateParticle( vPos, startlength )
		Creates a particle from the template. This particle can also be modified using the template functions.
	]]

	-- Moves and kills the particles
	local t_sfp = {}
	local function ParticleTick()
		if #t_sfp < 1 then return end
		local z_view = StormFox.util.GetCalcView().pos.z
		local fr = FrameTime() * 60 -- * game.GetTimeScale()
		local die = {}
		local gg = GLGravity() -- Global Gravity
		for n,t in ipairs(t_sfp) do
			local part = t[2]
			-- The length it moves (Could also be negative)
			local move = part.g
			if not part:GetIgnoreGravity() then
				move = part.g * gg 
			end
			part.curlength = part.curlength - move * fr * 10
			-- Check if it dies
			if move > 0 then
				local zp = part:CalcPos().z
				if zp < part.endpos.z then
					-- Hit ground
					table.insert(die, n)
				elseif zp < z_view - part.r_H or zp > z_view + part.r_H then
					-- Die in air
					part.hitType = SF_DOWNFALL_HIT_NIL
					table.insert(die, n)
				end
			elseif move < 0 then -- It moves up in the sky. Should allways be hittype SF_DOWNFALL_HIT_NIL
				if part:CalcPos().z > z_view + part.r_H then
					-- Die
					table.insert(die, n)
				end
			end
		end
		-- Kill particles
		for i = #die, 1, -1 do
			local t = table.remove(t_sfp, die[i])
			local part = t[2]
			if part.hitType ~= SF_DOWNFALL_HIT_NIL and part.OnHit then
				part:OnHit( part.endpos, part:GetHitNormal(), part.hitType )
			end
		end
	end
	-- Renders all particles. t_sfp should be in render-order
	local function ParticleRender()
		for _,t in ipairs(t_sfp) do
		--	render.DrawLine(t[2]:GetPos(), t[2].endpos, color_white, true)
			t[2]:Render()
		end
	end

	-- Adds a particle.
	function StormFox.DownFall.AddTemplateSimple( tTemplate, vEndPos, hitType, hitNorm, nDistance )
		local part = tTemplate:CreateParticle( vEndPos, vNorm, hitType, hitNorm )
		if not nDistance then
			local p = StormFox.util.GetCalcView().pos
			nDistance = Vector(p.x,p.y,vEndPos.z):Distance( vEndPos )
		end
		-- Add by distance
		local n = #t_sfp
		local t = {nDistance, part}
		if n < 1 then
			table.insert(t_sfp, t)
		else
			for i=1,n do
				if nDistance > t_sfp[i][1] then
					table.insert(t_sfp, i, t)
					return part
				end
			end
			table.insert(t_sfp, n, t)
		end
		return part
	end

	-- Tries to add a particle. Also has cache build in.
	function StormFox.DownFall.AddTemplate( tTemplate, nDistance, traceSize, vNorm )
		vNorm = vNorm or StormFox.Wind.GetNorm()
		local vEnd, nHitType, vCenter, hitNorm = StormFox.DownFall.CalculateDrop( nDistance, traceSize, 1, vNorm )
		-- pos,n,offset, hitNorm
		if not vEnd then 
			if tTemplate.m_cache then
				local t = table.remove(tTemplate.m_cache, 1)
				vEnd = t[1]
				nHitType = t[2]
				vCenter = t[3]
				hitNorm = t[4]
			else
				return false 
			end
		end -- Couldn't locate a position for the partice
		--debugoverlay.Cross(vEnd, 15, 1, Color(255,255,255), false)
		if not tTemplate.m_cache then tTemplate.m_cache = {} end
		if table.insert(tTemplate.m_cache, {vEnd,nHitType, vCenter, hitNorm}) > 10 then
			table.remove(tTemplate.m_cache,1)
		end
		return StormFox.DownFall.AddTemplateSimple( tTemplate, vEnd, nHitType, hitNorm, nDistance )
	end

	-- Returns the interval for the given template
	function StormFox.DownFall.CalcTemplateTimer( tTemplate )
		local P = 0.5 + StormFox.Weather.GetProcent() * 0.5
		local QT = 6 + max(1, StormFox.Client.GetQualityNumber())
		local totalL = QT * P * 10000
		local mL = (tTemplate.r_H / math.abs( tTemplate.g )) / totalL
		-- Safty. This slowly scales the amount of particles if it is 500 or above.
		if #t_sfp >= 500 then
			return mL * (1.90526 - 0.00178947 * #t_sfp)
		end
		return mL
	end

	-- Automaticlly spawns particles
	function StormFox.DownFall.SmartTemplate( tTemplate, nDistance, traceSize, vNorm  )
		local t = CurTime() - (tTemplate.s_timer or 0)
		local n = StormFox.DownFall.CalcTemplateTimer( tTemplate )
		if t > n then
			local m = FrameTime() / n
			tTemplate.s_timer = CurTime()
			for i = 1, math.min(m,12) do
				StormFox.DownFall.AddTemplate( tTemplate, nDistance, traceSize, vNorm )
			end
		end
	end

	hook.Add("Think","StormFox.Downfall.Tick", ParticleTick)
	hook.Add("PostDrawTranslucentRenderables", "StormFox.Downfall.Render", function(depth,sky)
		if depth or sky then return end -- Don't render in skybox or depth.
		-- Render particles on the floor
		_STORMFOX_PEM:Draw()
		_STORMFOX_PEM2d:Draw()
		if LocalPlayer():WaterLevel() >= 3 then return end -- Don't render SF particles under wanter.
		ParticleRender() -- Render sf particles
	end)
	function StormFox.DownFall.DebugList()
		return t_sfp
	end
end


