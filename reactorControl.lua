-- The program charges the capacitor, if the energy level (in percent) gets below this value
local energyLowerLimit         = 10

-- The program stops charging the capacitor, if the energy level (in percent) gets above this value
local energyUpperLimit         = 90

-- The number of capacitor blocks in the multi-block capacitor bank. Wrong values will cause
-- incorrect power measurements.
-- This value is ignored, if you don't use an EnderIO Capacitor Bank as energy storage.
local capacitorCount           = 4

-- The maximum fluid flow rate per turbine
local turbineMaxFluidFlowRate  = 1900

-- The maximum safe RPM for the turbines
local turbineMaxSafeSpeed      = 1900

-- The program will keep the turbines spinning on the desired speed level. If the speed level of
-- one turbine goes below this limit, the programm starts accelerating until the desired speed
-- level + the desired speed bonus is reached
local turbineDesiredSpeed      = 1800
local turbineDesiredSpeedBonus = 25

-- The reactor specific control rod levels. This option prevents to reactor from overheating.
-- Define a table with one entry for each connected turbine, where the first, second, .. specifies  
-- the control rod level, that is sufficient to fully power 1, 2, .. turbine(s).
local autoAdjustControlRods    = true
-- Control Rod Levels for the reactor found here: 
-- http://br.sidoh.org/#reactor-design?length=7&width=7&height=7&activelyCooled=true&controlRodInsertion=100&layout=2O3R4O3R2O3RX5R3X5RX3R2O3R4O3R2O
local controlRodLevels         = { 83, 66, 49, 32, 14, 0}

-- The reactor program tick interval. Recommended range is between 0.5 and 1.0 seconds.
local tickInterval             = 0.5

--================================================================================================--

-- Helper functions
local function findPeripherals(_type)
  local p = {}
  for _, name in ipairs(peripheral.getNames()) do
    if (peripheral.getType(name) == _type) then
      table.insert(p, name)
    end
  end
  return p
end

-- Internal constants
-- Uses the internal energy buffer of the connected turbines
local using_internal    = true
-- EnderIO Capacitor Bank
local using_ender_io    = false
-- Draconic Evolution Energy Core
local using_draconic    = false
-- Thermal Expansion Energy Cell
local using_thermal_exp = false

-- Energy Storage
local ender_io_cap_bank    = nil
local draconic_energy_core = nil
local thermal_exp_cell     = {}

-- Internal variables
local reactor              = nil
local turbines             = {}
local turbineAccelerating  = {}

-- Internal functions
local function initPeripherals()
  -- Constants
  local TYPE_NAME_REACTOR                    = "BigReactors-Reactor"
  local TYPE_NAME_TURBINE                    = "BigReactors-Turbine"
  local TYPE_NAME_STORAGE_ENDER_IO           = "tile_blockcapacitorbank_name"
  local TYPE_NAME_STORAGE_DRACONIC_EVOLUTION = "draconic_rf_storage"
  -- TODO: figure out what this is supposed to be
  local TYPE_NAME_STORAGE_THERMAL_EXPANSION  = "something_cell"
  -- Reactor
  local list = findPeripherals(TYPE_NAME_REACTOR)
  if (#list < 1) then
    error("No reactor connected")
  elseif (#list > 1) then
    print("Multiple reactors connected")
  end
  reactor = peripheral.wrap(list[1])
  print("Wrapped reactor " .. list[1])
  if (not reactor.isActivelyCooled) then
    error("This reactor is not actively cooled")
  end
  -- Turbines
  local list = findPeripherals(TYPE_NAME_TURBINE)
  if (#list < 1) then
    error("No turbines connected")
  end
  print(tostring(#list) .. " turbines connected")
  for index, turbineName in pairs(list) do
    table.insert(turbines, peripheral.wrap(turbineName))
    table.insert(turbineAccelerating, false)
    print("Wrapped turbine " .. turbineName)
  end
  -- Energy Storage
  -- ENDER IO
  local list = findPeripherals(TYPE_NAME_STORAGE_ENDER_IO)
  if (#list == 1) then
    ender_io_cap_bank = peripheral.wrap(list[1])
    using_ender_io = true
    print("Wrapped energy storage " .. list[1])
  end
  -- DRACONIC EVOLUTION
  local list = findPeripherals(TYPE_NAME_STORAGE_DRACONIC_EVOLUTION)
  if (#list == 1) then
    draconic_energy_core = peripheral.wrap(list[1])
    using_draconic = true
    print("Wrapped energy storage " .. list[1])
  end
  -- THERMAL EXPANSION
  local list = findPeripherals(TYPE_NAME_STORAGE_THERMAL_EXPANSION)
  if (#list > 0) then
    for index, cellName in pairs(list) do
		table.insert(thermal_exp_cell, peripheral.wrap(list[index]))
	end
	using_thermal_exp = true
    print("Wrapped energy storage " .. list[1])
  end
  print("Using internal energy storage")
end

local function getMaxEnergyStored()
  local total = 0
  if (using_internal) then
    total = total + (1000000 * #turbines)
  end
  if (using_ender_io) then
    total = total + ender_io_cap_bank.getMaxEnergyStored() * capacitorCount
  end	
  if (using_draconic) then
    total = total + draconic_energy_core.getMaxEnergyStored()
  end
  if (using_thermal_exp) then
	for index, cellName in pairs(thermal_exp_cell) do
		total = total + thermal_exp_cell[index].getMaxEnergyStored()
	end
  end
  return total
  error("unreachable block in getMaxEnergyStored")
end

local function getEnergyStored()
  local energy = 0
  if (using_internal) then
    for index, turbine in pairs(turbines) do
      energy = energy + turbines[index].getEnergyStored()
    end
  end
  if (using_ender_io) then
    energy = energy + (ender_io_cap_bank.getEnergyStored() * capacitorCount)
  end
  if (using_draconic) then
    energy = energy + draconic_energy_core.getEnergyStored()
  end 
  if(using_thermal_exp) then
	for index, cellName in pairs(thermal_exp_cell) do
		energy = energy + thermal_exp_cell[index].getEnergyStored()
	end
  end
  return energy
  error("unreachable block in getEnergyStored")
end

local function getEnergyStoredPercent()
  return math.floor(getEnergyStored() / getMaxEnergyStored() * 100)
end

local function reactorSetControlRodLevelByNumberOfActiveTurbines(numTurbines)
  if (not autoAdjustControlRods) then
    return
  end
  local controlRodLevel = 0
  if (numTurbines == 0) then
    controlRodLevel = 100
  else
    controlRodLevel = controlRodLevels[numTurbines]
  end
  reactor.setAllControlRodLevels(controlRodLevel)
end

local function turbinesSetActive(active)
  for index, turbine in pairs(turbines) do
    turbine.setActive(active)
  end
end

local function turbinesSetCoilsEngaged(engaged)
  for index, turbine in pairs(turbines) do
    turbine.setInductorEngaged(engaged)
  end
end

local function checkTurbineSpeed()
	for index, turbine in pairs(turbines) do
		if(turbines[index].getRotorSpeed() > turbineMaxSafeSpeed)
			turbineAccelerating[index] = false
			turbines[index].setActive(false)
			turbines[index].setInductorEngaged(true)
		end
		else
			turbines[index].setActive(true)
			turbines[index].setFluidFlowRateMax(turbineMaxFluidFlowRate)
		end
	end
end

-- Main
local isCharging     = false
local isAccelerating = false

local function mainTick()
    turbinesSetActive(true)
    print("Charging    : " .. tostring(isCharging))
    print("Accelerating: " .. tostring(isAccelerating))
    local activeTurbines = 0
    if (isCharging) then
      activeTurbines = #turbines
      if (getEnergyStoredPercent() >= energyUpperLimit) then
        isCharging = false
        isAccelerating = false
        if (autoAdjustControlRods) then
          reactor.setAllControlRodLevels(100)
        else
          reactor.setActive(false)
        end
        turbinesSetCoilsEngaged(false)
      end
    else
      if (getEnergyStoredPercent() <= energyLowerLimit) then
        isCharging = true
        isAccelerating = false
        for index, turbine in pairs(turbines) do
          turbineAccelerating[index] = false
          turbine.setFluidFlowRateMax(turbineMaxFluidFlowRate)
        end
        if (autoAdjustControlRods) then
           reactorSetControlRodLevelByNumberOfActiveTurbines(#turbines)
        else
          reactor.setActive(true)
        end
        turbinesSetCoilsEngaged(true)
      else
        local doAccelerate = false
        for index, turbine in pairs(turbines) do
          local turbineSpeed = turbine.getRotorSpeed()
          print("Turbine " .. tostring(index) .. " @ " .. 
            tostring(turbineSpeed) .. "RPM - " .. tostring(turbineAccelerating[index]))
          if (((not turbineAccelerating[index]) and (turbineSpeed < turbineDesiredSpeed)) or
            (turbineAccelerating[index] and 
            (turbineSpeed < turbineDesiredSpeed + turbineDesiredSpeedBonus))) then    
            doAccelerate = true
            turbineAccelerating[index] = true
            activeTurbines = activeTurbines + 1
            turbine.setFluidFlowRateMax(turbineMaxFluidFlowRate) 
          end
          if ((not turbineAccelerating[index]) or (turbineAccelerating[index] and 
            (turbineSpeed >= turbineDesiredSpeed + turbineDesiredSpeedBonus))) then  
            turbineAccelerating[index] = false
            turbine.setFluidFlowRateMax(0)
          end
        end
        if (doAccelerate and (not isAccelerating)) then
          isAccelerating = true
          if (not autoAdjustControlRods) then
            reactor.setActive(true) 
          end
        elseif ((not doAccelerate) and isAccelerating) then
		  checkTurbineSpeed()
          isAccelerating = false
          if (not autoAdjustControlRods) then
            reactor.setActive(false) 
          end
        end
      end
    end
    print("Turbines online: " .. tostring(activeTurbines))
    reactorSetControlRodLevelByNumberOfActiveTurbines(activeTurbines)
    print("Control rod lvl: " .. tostring(reactor.getControlRodLevel(1)))
end

local function main()
  initPeripherals()
  if (autoAdjustControlRods) then
    if (#turbines > #controlRodLevels) then
      error("Invalid controlRodLevels value. Not enough table entries for the amount " ..
        "of connected turbines.")    
    end
    reactor.setAllControlRodLevels(100)
    reactor.setActive(true)
  else
    reactor.setActive(false)
  end
  turbinesSetCoilsEngaged(false)
  while (true) do
    mainTick()
    local loopTimerId = os.startTimer(tickInterval) 
    while (true) do
      local event, timerId = os.pullEvent("timer")    
      if (timerId == loopTimerId) then
        break
      end
    end
  end
end

main()
