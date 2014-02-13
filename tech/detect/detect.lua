-- TODO
-- future-loading? (use coroutine.yield() and coroutine.resume())
---- hints_ suggested doing a full scan, splining over the results, and finding maxima (analytical?!)
-- sparse scanning (interlace + use collision data)
-- particle FX?
--

--local neighbor3x3 = { {1,0}, {1,1}, {0,1}, {-1,1}, {-1,0}, {-1,-1}, {0,-1}, {1,-1} }
-- 2-neighbors
local neighbor3x3 = { 
    [4]={-1,1},  [3]={0,1},  [2]={1,1},

    [5]={-1,0},              [1]={1,0},

    [6]={-1,-1}, [7]={0,-1}, [8]={1,-1} 
}

-- 4-neighbors
local neighbor5x5 = { 
    {1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1},
    {2,0},{2,1},{2,2},{1,2},{0,2},{-1,2},{-2,2},{-2,1},{-2,0},{-2,-1},{-2,-2},{-1,-2},{0,-2},{1,-2},{2,-2},{2,-1}
 }



-- set this flag to true to test mats, not mods (debugging)
local debugMaterial = false
local debugVerbosity = 0 
-- verbosity levels (cumulative)
--  0 : off (no debug output)
--  1 : single-line summary, functional tracing only
--  2 : single-line detail, functional output etc.
--  3 : print everything (basically guaranteed to lag/freeze the game)

function debugLog(minlevel,str,...)
   if debugVerbosity >= minlevel then
        world.logInfo(str,...)
   end 
end

function init()
  data.cachettl = tech.parameter("cachettl")
  data.scoringPower = tech.parameter("scoringPower")
  data.minScore = tech.parameter("minScore")
  data.soundDelay = tech.parameter("soundDelay")
  data.maxSoundDelay = tech.parameter("maxSoundDelay")
  data.minScanDelay = tech.parameter("minScanDelay")
  data.farDist = tech.parameter("farDist")
  data.nearDist = tech.parameter("nearDist") 
  data.detectRange = tech.parameter("detectRange")
  data.targets = {["coalsample"]="coal",["coppersample"]="copper",["silversample"]="silverore"}
  if not data.pingTargets then
    data.pingTargets = { }
  end
  world.logInfo("pingtargets is %s",data.pingTargets)
  
  scanDelay = 0
  results = {}
  cache = {}
  searchpattern = {}
  lastScan = os.clock()
  nextOreSound = nil
  flushtime = 0
  scantime = 0
  scanning = false
  
  startupsnd = "/sfx/oredetector/startupbeep.wav"
  shutdownsnd = "/sfx/oredetector/shutdownbeep.wav"
  soundstr = "/sfx/beep.ogg"
  flushedsomething = false
  currenttarget = 1 
 
  debugLog(1,"detect.lua:init(): Initialized detect.lua")
  generateSearchPattern()
  --tech.setAnimationState("indicate","indicate")
end

function scan()
    local origpos = tech.position()
    local maxscore = { {}, 0 } 
    local dist = -1
    results = {}
    scantime = os.clock()
    flushtime = scantime + data.cachettl
    debugLog(1,"detect.lua:scan(): Running scan()...")
    -- if this ends up being future-loaded, run with coroutine.create(scan)
    if nextOreSound then return nil end
    for i,ring in pairs(searchpattern) do
        --table.insert(results,scanRing(ring,origpos))
        scanRing(ring,origpos)
    end

    local scoring = {}
    for px,t in pairs(results) do
        for py,mod in pairs (t) do 
            if not scoring[px] then scoring[px]={} end
            -- TODO: uh I don't remember what I was doing here but this looks world-wrap unsafe
            dist = math.sqrt(math.pow(px-origpos[1],2)+math.pow(py-origpos[2],2))
            --dist = world.magnitude({px,py},origpos)
            --if dist < 1 then dist = 1 end
            scoring[px][py] = scoreTile({px,py},mod,dist)
            debugLog(2,"detect.lua:scan(): Now scoring %s, dist is %d, score is %d",{px,py},dist,scoring[px][py])
            if scoring[px][py] > maxscore[2] then 
                debugLog(2,"detect.lua:scan(): New max score!  Old was %s, new is %s",maxscore,{ {px,py}, scoring[px][py] })
                maxscore = { {px,py}, scoring[px][py] } 
            end
        end
    end
    debugLog(2,"detect.lua:scan(): Max score is %s",maxscore)
    if not maxscore[1][1] then 
        scanDelay = 1.0 -- switch to 'passive' scan
        return nil 
    end
    scanDelay = 0.0 -- switch to 'active' scan
    
    soundstr = distanceParameters({maxscore[1][1]-origpos[1],maxscore[1][2]-origpos[2]})
    nextOreSound = os.clock() + math.min(data.soundDelay * 1/maxscore[2],data.maxSoundDelay)
    if flushedsomething then debugLog(2,"detect.lua:scan(): flushed something this scan") end
end

function distanceParameters(pos)
    local dist = world.magnitude(pos)
    if dist >= data.farDist then
        soundstr = "/sfx/oredetector/coal/far.wav"
        tech.setAnimationState("indicate","off")
    elseif dist < data.farDist and dist >= data.nearDist then
        soundstr = "/sfx/oredetector/coal/medium.wav"
        tech.setAnimationState("indicate","off")
    elseif dist < data.nearDist then
        soundstr = "/sfx/oredetector/coal/close.wav"
        tech.setAnimationState("indicate","indicate")
        tech.rotateGroup("indicator",math.atan2(pos[2],pos[1]))
    end 
    return soundstr
end

function scoreTile(pos,target,dist)
    local numore = 1
    for i=1,8 do
        local neighbor = {round(pos[1]+neighbor3x3[i][1]),round(pos[2]+neighbor3x3[i][2])}
        if results[neighbor[1]] and results[neighbor[1]][neighbor[2]] then 
            debugLog(2,"detect.lua:scoreTile() Incrementing score at %s...",neighbor)
            numore=numore+1 
        end
    end 
    if numore < data.minScore then return 0 end
    return numore/math.pow(dist+1,data.scoringPower)
end

function scanRing(ring,origpos)
	local res = {}
	for j,pos in pairs(ring) do
		local dist = pos[1]*pos[1]+pos[2]*pos[2]
		local scanpos = {round(origpos[1]+pos[1]),round(origpos[2]+pos[2])}
		local usecache = (dist > 25)
		res[scanpos] = scanTile(scanpos,dist,usecache)
    end
	return res
end

function scanTile(scanpos,dist,usecache)
	local res = nil 
	local ctile = nil

	-- this will initialize the child table as necessary
	if not cache[scanpos[1]] then cache[scanpos[1]] = {} end
	xcache = cache[scanpos[1]]
	ctile = xcache[scanpos[2]]
	
    debugLog(3,"detect.lua:scanTile(): Cached tile is %s",ctile)
    if ctile and ctile[2] and scantime>=ctile[2] then flushedsomething = true end
	if ctile and usecache and scantime < ctile[2] then
		debugLog(2,"detect.lua:scanTile(): Using cached result for %s...",scanpos)
		res = ctile[1]
	else
		res = world.mod(scanpos,"foreground") or "empty"
        if debugMaterial then res = world.material(scanpos,"foreground") or "empty" end 
		cache[scanpos[1]][scanpos[2]] = { res, flushtime }
    end
	if isTargetOre(res) then 
        if not results[scanpos[1]] then results[scanpos[1]] = {} end
        results[scanpos[1]][scanpos[2]] = res 
        debugLog(3,"detect.lua:scanTile(): Result at %s is %s",scanpos,res)
    end
	return res
end

function isTargetOre(candidate)
    for i,v in ipairs(data.pingTargets) do
        -- two tests allows catching everything without weird item names
        if candidate == v or (candidate .. "ore") == v then return i end
    end
    return false
end

function generateSearchPattern()
    searchpattern = { 
        { {1,0}, {0,1}, {-1,0}, {0,-1} } 
    }
    for i=2,data.detectRange do
        table.insert(searchpattern,createOctagon(i))
    end
    debugLog(2,"detect.lua:generateSearchPattern(): Full searchpattern is %s",searchpattern)
end

function round(num)
    return math.floor(num + 0.5)
end

function createOctagon(i)
    local perimeter = 4*math.ceil(i/2) + (3-i%2)*4*math.floor(i/2)
    local ret = {}
    
    for j=0,perimeter-1 do
    table.insert(ret,
        {
            round(i*math.cos(j*2*math.pi/perimeter)),
            round(i*math.sin(j*2*math.pi/perimeter))
        })
    end
    return ret
end

function sizeOfTable(t)
    local n = 0
    for _,_ in pairs(t) do n = n+1 end
    return n
end

function addTargetOre(target)
    if not type(target) == string or isTargetOre(target) then 
        return false 
    end
    debugLog(-1,"detect.lua:addTargetOre(): Starting table is %s",data.pingTargets)
    if sizeOfTable(data.pingTargets) >= 3 then
        debugLog(-1,"detect.lua:addTargetOre(): Removing target %s from data.pingTargets",data.pingTargets[1])
        table.remove(data.pingTargets,1)
    end
    debugLog(-1,"detect.lua:addTargetOre(): Adding target %s to data.pingTargets",target)
    table.insert(data.pingTargets,target)
    debugLog(-1,"detect.lua:addTargetOre(): Ending table is %s",data.pingTargets)
    return true
end

function removeTargetOre(target)
    tablepos = isTargetOre(target)
    if not type(target) == string or not tablepos then
        return false
    end
    debugLog(-1,"detect.lua:removeTargetOre(): Starting table is %s",data.pingTargets)
    table.remove(data.pingTargets,tablepos)
    debugLog(-1,"detect.lua:removeTargetOre(): Ending table is %s",data.pingTargets)
    return true
end

function input(args)
  if args.moves["special"] == 1 then
    return "detect"
  end
  
  if args.moves["special"] == 2 then
    local item = checkHandSample()
    if item then
        addTargetOre(string.gsub(item,"sample$",""))
    end
  end
  
  if args.moves["special"] == 3 then
    
    tech.setParentAppearance("normal")
    local item = checkHandSample()
    if item then
        removeTargetOre(string.gsub(item,"sample$",""))
    end
  end
  
  return nil
end

function checkHandSample()
    primitem = world.entityHandItem(tech.parentEntityId(),"primary")
    altitem = world.entityHandItem(tech.parentEntityId(),"alt")
    debugLog(2,"detect.lua:checkHandSample(): Primary hand item is %s",primitem)
    debugLog(2,"detect.lua:checkHandSample(): Alt hand item is %s",altitem)
    if primitem and string.find(primitem,"sample$") then
        return primitem
    elseif altitem and string.find(altitem,"sample$") then
        return altitem
    end
    return nil
end

function update(args)
  --tech.setAnimationState("indicate","indicate")
  --tech.rotateGroup("indicator",(os.clock()%60)*2*math.pi/1.5)
  
  
  if nextOreSound 
  and os.clock() > nextOreSound then
    nextOreSound = nil
    tech.playImmediateSound(soundstr)
  end
  
  if scanning 
  and (os.clock()-lastScan) > (data.minScanDelay + scanDelay)
  and string.find(tostring(world.entityHandItem(tech.parentEntityId(),"primary")),"pickaxe") then
    lastScan=os.clock()
    scan()
  end
    
  if not (scanning and string.find(tostring(world.entityHandItem(tech.parentEntityId(),"primary")),"pickaxe")) then 
    tech.setAnimationState("indicate","off")
  end
  
  if args.actions["detect"] then
    scanning = not scanning
    if scanning then 
      tech.playImmediateSound(startupsnd)
    else
      tech.playImmediateSound(shutdownsnd)
    end
    nextOreSound = nil
    debugLog(1,"detect passed as an arg in detect.lua:update(), setting scanning to %s",scanning)
    return nil
  end
end
