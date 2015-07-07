--[[ 
	Lua functions for datadriven Puck spells Illusory Orb and Waning Rift
	Source: https://github.com/Pizzalol/SpellLibrary
	Modified by Mayheim for 'puck arena' http://steamcommunity.com/sharedfiles/filedetails/?id=474108636
	Date: 06-July-2015
]]

--[[
	Author: Ractidous
	Date: 02.16.2015.
	Create a linear projectile, then keep it tracked.
]]
function CastIllusoryOrb( event )
	
	local caster	= event.caster
	local ability	= event.ability
	local point		= event.target_points[1]

	local damage			= event.damage		-- Add damage to datadriven spell: "OnSpellStart" { "RunScript" { "damage"		"%AbilityDamage"
	local radius			= event.radius
	local maxDist			= event.max_distance
	local orbSpeed			= event.orb_speed
	local visionRadius		= event.orb_vision
	local visionDuration	= event.vision_duration
	local numExtraVisions	= event.num_extra_visions

	local travelDuration	= maxDist / orbSpeed
	local extraVisionInterval = travelDuration / numExtraVisions

	local casterOrigin		= caster:GetAbsOrigin()
	local targetDirection	= ( ( point - casterOrigin ) * Vector(1,1,0) ):Normalized()
	local projVelocity		= targetDirection * orbSpeed

	local startTime		= GameRules:GetGameTime()
	local endTime		= startTime + travelDuration

	local numExtraVisionsCreated = 0
	local isKilled		= false

	-- Add context values to correctly apply damage in OnUnitHit
	ability:SetContextNum("reflectCaster", caster:GetEntityIndex(), 0)
	ability:SetContextNum("orbDamage", damage, 0)

	-- Make Ethereal Jaunt active
	local etherealJauntAbility = ability.illusory_orb_etherealJauntAbility
	etherealJauntAbility:SetActivated( true )

	-- Check if the orb was reflected and move casterOrigin to position of reflected orb, change direction if necessary
	if ( event.reflected and event.caster == event.originalCaster ) then 	-- caster has hit his own orb
		casterOrigin 	= event.reflected
	elseif event.reflected then		-- caster has hit enemy orb, change direction back towards the enemy
		point 			= event.originalCaster:GetAbsOrigin()
		casterOrigin 	= event.reflected
		targetDirection = ( ( point - casterOrigin ) * Vector(1,1,0) ):Normalized()
		projVelocity	= targetDirection * orbSpeed

		-- deactivate Jaunt when orb is reflected
		etherealJauntAbility:SetActivated( false )
	end

	-- Create linear projectile
	local projID = ProjectileManager:CreateLinearProjectile( {
		Ability				= ability,
		EffectName			= event.proj_particle,
		vSpawnOrigin		= casterOrigin,
		fDistance			= maxDist,
		fStartRadius		= radius,
		fEndRadius			= radius,
		Source				= caster,
		bHasFrontalCone		= false,
		bReplaceExisting	= false,
		iUnitTargetTeam		= DOTA_UNIT_TARGET_TEAM_ENEMY,
		iUnitTargetFlags	= DOTA_UNIT_TARGET_FLAG_NONE,
		iUnitTargetType		= DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
		fExpireTime			= endTime,
		bDeleteOnHit		= false,
		vVelocity			= projVelocity,
		bProvidesVision		= true,
		iVisionRadius		= visionRadius,
		iVisionTeamNumber	= caster:GetTeamNumber(),
	} )

	--print("projID = " .. projID)

	-- Create sound source
	local thinker = CreateUnitByName( "npc_dota_thinker", casterOrigin, false, caster, caster, caster:GetTeamNumber() )
	thinker:SetContext("isOrb", "1", 0) --  Add context to thinker for function WaningRiftReflect
	ability:ApplyDataDrivenModifier( caster, thinker, event.proj_modifier, { duration = -1 } ) 

	if event.reflected then
		-- Emit different sound when orb is reflected
		thinker:EmitSound("Hero_VengefulSpirit.MagicMissile")	
	else
		thinker:EmitSound("Hero_Puck.Illusory_Orb")
	end

	--
	-- Replace Ethereal Jaunt function
	--
	etherealJauntAbility.etherealJaunt_cast = function ( )
		-- Remove the projectile
		ProjectileManager:DestroyLinearProjectile( projID )

		-- Blink
		FindClearSpaceForUnit( caster, thinker:GetAbsOrigin(), false )

		-- Kill
		isKilled = true

		etherealJauntAbility.etherealJaunt_cast = nil
	end

	--
	-- Track the projectile
	--
	Timers:CreateTimer( function ( )
		
		local elapsedTime 	= GameRules:GetGameTime() - startTime
		local currentOrbPosition = casterOrigin + projVelocity * elapsedTime
		currentOrbPosition = GetGroundPosition( currentOrbPosition, thinker )

		-- Update position of the sound source
		thinker:SetAbsOrigin( currentOrbPosition )

		-- Try to create new extra vision
		if elapsedTime > extraVisionInterval * (numExtraVisionsCreated + 1) then
			ability:CreateVisibilityNode( currentOrbPosition, visionRadius, visionDuration )
			numExtraVisionsCreated = numExtraVisionsCreated + 1
		end

		-- Remove if the projectile has expired
		if elapsedTime >= travelDuration or isKilled then
			--print( numExtraVisionsCreated .. " extra vision created." )
			thinker:RemoveModifierByName( event.proj_modifier )
			etherealJauntAbility:SetActivated( false )

			thinker:RemoveSelf()
			return nil
		end

		-- If orb is reflected, create a new orb by recursively calling CastIllusoryOrb with additional key/value pairs:
		-- reflected, originalCaster
		if thinker:GetContext("reflectCaster") then -- This context is added in fuction WaningRiftReflect 
			local rCaster = EntIndexToHScript(thinker:GetContext("reflectCaster"))

			if ( rCaster ~= event.caster and rCaster:GetTeamNumber() == event.caster:GetTeamNumber() ) then
				-- If the orb was cast or reflected by an allie, we do nothing
			else
				local riftDamage = thinker:GetContext("waningRiftDamage") -- This context is added in fuction WaningRiftReflect 

				-- Destroy current orb, cast a new orb via recursion
				ProjectileManager:DestroyLinearProjectile( projID )
				CastIllusoryOrb( {
					caster				= rCaster,
					ability				= event.ability,
					target_points		= event.target_points,
					damage				= event.damage + riftDamage, -- Add damage for every time the orb is reflected
					radius				= event.radius,
					max_distance		= event.max_distance*1.2, 	 -- Add extra range
					orb_speed			= event.orb_speed*1.5,		 --	Speed orb up
					orb_vision			= event.orb_vision,
					vision_duration		= event.vision_duration,
					num_extra_visions	= event.num_extra_visions,
					proj_modifier 		= event.proj_modifier,
					proj_particle		= event.proj_particle,
					reflected			= thinker:GetAbsOrigin(),  	 -- The current position of the orb
					originalCaster		= event.caster,
				} )

				-- Remove old thinker
				thinker:RemoveModifierByName( event.proj_modifier )
				thinker:RemoveSelf()
				return nil
			end
		end

		return 0.03

	end )

end


-- Function used in place of datadriven damage to award kills correctly
function OnUnitHit( event )
	local caster = EntIndexToHScript(event.ability:GetContext("reflectCaster"))
	local damage = event.ability:GetContext("orbDamage")	-- the cumulative damage of the orb + every rift that has hit the orb
	local damage_table = {}

	damage_table.victim 		= event.target
	damage_table.attacker 		= caster
	damage_table.damage 		= damage
	damage_table.damage_type 	= DAMAGE_TYPE_MAGICAL
	damage_table.ability 		= event.ability

	ApplyDamage(damage_table)
end


--[[
	Author: Ractidous
	Date: 16.02.2015.
	Upgrade the sub ability and make inactive it.
]]
function OnUpgrade( event )
	local caster	= event.caster
	local ability	= event.ability
	local etherealJauntAbility = caster:FindAbilityByName( event.sub_ability )
	ability.illusory_orb_etherealJauntAbility = etherealJauntAbility

	if not etherealJauntAbility then
		print( "Ethereal jaunt not found. at heroes/hero_puck/illusory_orb.lua # OnUpgrade" )
		return
	end

	etherealJauntAbility:SetLevel( ability:GetLevel() )

	if etherealJauntAbility:GetLevel() == 1 then
		etherealJauntAbility:SetActivated( false )
	end
end


--[[
	Author: Ractidous
	Date: 16.02.2015.
	Cast Ethereal Jaunt.
]]
function CastEtherealJaunt( event )
	local ability = event.ability
	if ability.etherealJaunt_cast then
		ability.etherealJaunt_cast()
	end
end


--[[
	Author: Ractidous
	Date: 13.02.2015.
	Stop a sound on the target unit.
]]
function StopSound( event )
	StopSoundEvent( event.sound_name, event.target )
end


-- When Waning Rift is cast, find all Illusory Orbs in range and add necessary contexts
function WaningRiftReflect( event )
	local orbTable = {}
	orbTable = Entities:FindAllInSphere(event.caster:GetAbsOrigin(), event.radius)

	for _, orb in pairs(orbTable) do
		if orb:GetContext("isOrb") then
			orb:SetContextNum("reflectCaster", event.caster:GetEntityIndex(), 0)
			orb:SetContextNum("waningRiftDamage", event.damage, 0) -- add damage to datadriven spell: "OnSpellStart" { "RunScript" { "damage"		"%AbilityDamage"
		end
	end
end