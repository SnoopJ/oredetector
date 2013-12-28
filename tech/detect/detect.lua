-- TODO
-- future-loading? (use coroutine.yield() and coroutine.resume())
---- hints_ suggested doing a full scan, splining over the results, and finding maxima (analytical?!)
-- sparse scanning (interlace + use collision data)
-- particle FX?

local searchpattern = {}
local results = {}
local lastScan = os.clock()
local nextOreSound = nil
local soundDelay = 150/1000
local scoringPower = 0.7 
local scanning = false
local cache = {}
local cachettl = 30
local neighbor3x3 = { {1,0}, {1,1}, {0,1}, {-1,1}, {-1,0}, {-1,-1}, {0,-1}, {1,-1} }
local pingTargets = { ["coal"]=true, ["dirt"]=false, ["cobblestone"]=false }
local maxSoundDelay = 2
local minScanDelay = 0.1
local scanDelay = 0
local minScore = 3
local soundstr = "/sfx/beep.ogg"
local farDist = 30
local mediumDist = 15
local flushtime = 0
local scantime = 0
local flushedsomething = false
local targets = {"coal","copperore","silverore"}
local i = 1

-- set this flag to true to test mats, not mods (debugging)
local debug = false

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
  debugLog(1,"detect.lua:init(): Initialized detect.lua")
  data.detectRange = 45
  data.origPos = tech.position()
  generateSearchPattern()
end

function scan()
    local origpos = tech.position()
    local maxscore = { {}, 0 } 
    results = {}
    flushtime = os.clock() + cachettl
    scantime = os.clock()
    debugLog(1,"detect.lua:scan(): Running scan()...")
    -- if this ends up being future-loaded, run with coroutine.create(scan)
    if nextOreSound then return nil end
    for i,ring in pairs(searchpattern) do
        --table.insert(results,scanRing(ring,origpos))
        scanRing(ring,origpos)
    end

    local num = 0
    local scoring = {}
    for px,t in pairs(results) do
        for py,mod in pairs (t) do 
            num = num + 1
            if not scoring[px] then scoring[px]={} end
            dist = math.sqrt(math.pow(px-origpos[1],2)+math.pow(py-origpos[2],2))
            if dist < 1 then dist = 1 end
            scoring[px][py] = scoreTile({px,py},mod,dist)
            debugLog(2,"detect.lua:scan(): Now scoring %s, dist is %d, score is %d",{px,py},dist,scoring[px][py])
            if scoring[px][py] > maxscore[2] then maxscore = { {px,py}, scoring[px][py] } end
        end
    end
    debugLog(2,"detect.lua:scan(): Max score is %s",maxscore)
    if not maxscore[1][1] then 
        scanDelay = 1.0 -- switch to 'passive' scan
        return nil 
    end
    scanDelay = 0.0 -- switch to 'active' scan
    dist = math.sqrt(math.pow(maxscore[1][1]-origpos[1],2)+math.pow(maxscore[1][2]-origpos[2],2))
    if dist >= farDist then
        soundstr = "/sfx/oredetector/coal/far.wav"
    elseif dist < farDist and dist >= mediumDist then
        soundstr = "/sfx/oredetector/coal/medium.wav"
    elseif dist < mediumDist then
        soundstr = "/sfx/oredetector/coal/close.wav"
    end 
    nextOreSound = os.clock() + math.min(soundDelay * 1/maxscore[2],maxSoundDelay)
    world.spawnProjectile("oreflash2",maxscore[1],tech.parentEntityId(),{0,0},false)
    if flushedsomething then debugLog(2,"detect.lua:scan(): flushed something this scan") end
end

function scoreTile(pos,target,dist)
    local score = 1
    for i=1,8 do
        local neighbor = {round(pos[1]+neighbor3x3[i][1]),round(pos[2]+neighbor3x3[i][2])}
        if results[neighbor[1]] and results[neighbor[1]][neighbor[2]] then 
            debugLog(2,"detect.lua:scoreTile() Incrementing score at %s...",neighbor)
            score=score+1 
        end
    end 
    if score < minScore then return 0 end
    return score/math.pow(dist+1,scoringPower)
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
        if debug then res = world.material(scanpos,"foreground") or "empty" end 
		cache[scanpos[1]][scanpos[2]] = { res, flushtime }
    end
	if pingTargets[res] then 
        if not results[scanpos[1]] then results[scanpos[1]] = {} end
        results[scanpos[1]][scanpos[2]] = res 
        debugLog(3,"detect.lua:scanTile(): Result at %s is %s",scanpos,res)
    end
	return res
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
-- to nearest integer
    return math.floor(num + 0.5)
end

function createOctagon(i)
-- do stuff.  see the xcf file
    local perimeter = 4*math.ceil(i/2) + (3-i%2)*4*math.floor(i/2)
    local ret = {}
    --debugLog(3,"'Perimeter' of octagon %d is %d",i,perimeter)  
    
    for j=0,perimeter-1 do
    table.insert(ret,
        {
            round(i*math.cos(j*2*math.pi/perimeter)),
            round(i*math.sin(j*2*math.pi/perimeter))
        })
    end
    return ret
end

function input(args)
  if args.moves["special"] == 1 then
    return "detect"
  end
  if args.moves["special"] == 2 then
    --debugLog(1,"detect.lua:input(): Manually flushing cache")
    --cache = {}
    world.spawnProjectile("detectcoal",tech.position(),tech.parentEntityId(),{0,0},false)
  end
  if args.moves["special"] == 3 then
--    tech.burstParticleEmitter("detectParticles")
    i = i + 1
    if i > 3 then i = 1 end
    tech.burstParticleEmitter("detect"..targets[i])
    return "mousepos"
  end
  
  return nil
end

function update(args)
  if args.actions["mousepos"] then
    local mpos = args.aimPosition 
    world.spawnProjectile("oreflash2", mpos, tech.parentEntityId(), {0,0}, false)
    world.logInfo("Mouse position is (%d,%d)",mpos[1],mpos[2])
  end
  
  if nextOreSound and os.clock() > nextOreSound then
    nextOreSound = nil
    tech.playImmediateSound(soundstr)
  end
  
  if (os.clock()-lastScan) > (minScanDelay + scanDelay) and scanning then
    lastScan=os.clock()
    scan()
  end
  
  if args.actions["detect"] then
    scanning = not scanning
    nextOreSound = nil
    debugLog(1,"detect passed as an arg in detect.lua:update(), setting scanning to %s",scanning)
    return nil
  end
end
