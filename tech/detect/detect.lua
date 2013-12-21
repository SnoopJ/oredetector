-- TODO
-- future-loading? (use coroutine.yield() and coroutine.resume())
-- glob detection/weighting (more ore = faster)
---- hints_ suggested doing a full scan, splining over the results, and finding maxima (analytical?!)
-- sparse scanning (interlace + use collision data)
-- particle FX?

local searchpattern = {}

local candidates = {}
local results = {}
local startTime = {}
local lastScan = os.clock()
local nextOreSound = nil
local soundDelay = 1/20
local pow = 1/4

function init()
  world.logInfo("Initialized detect.lua")
  data.detectRange = 45
  --data.detectRange = 20
  data.delayScan = false
  data.origPos = tech.position()
  generateSearchPattern()
 
  a = { 1=1,2=2,3=3 }
  b = { 1=2,2=2,3=1 }
  --int_ab = { 2=2 }
  int_ab = intersectTables(a,b)
  world.logInfo("Intersecting tables a,b, result is %s",int_ab)
end

--[[ example intersection
-----------------------]]--

function intersectTables(a,b)
    local c = {}
    for ka,va in pairs(a) do
        c[ka] = b[ka]
    end
    return c
end

function scan()
    local origpos = tech.position()
    origpos[2] = origpos[2]-1
    -- if this ends up being future-loaded, run with coroutine.create(scan)
    if not nextOreSound then
        for i,ring in pairs(searchpattern) do
            for j,pos in pairs(ring) do
                
                local scanpos = {origpos[1]+pos[1],origpos[2]+pos[2]}
                
                local fmod = world.mod(scanpos,"foreground")
                
                --world.logInfo("At %s was %s",scanpos,fmod)
                if fmod then
                    --world.logInfo("Found mod %s at relative pos (%d,%d)",fmod,pos[1],pos[2])
                end
                -- bozo detection (any ol' piece of ore)
                if fmod == "iron" then
                    --tech.playImmediateSound("/sfx/beep2.wav")
                    nextOreSound = os.clock()+
                    soundDelay*i
                    world.logInfo("In detect.lua:scan() Iron found, should play a sound shortly (%d seconds)",nextOreSound-os.clock())
                    return nil
                end
            end
        end
    end
end

function generateSearchPattern()
    searchpattern = { 
        { {1,0}, {0,1}, {-1,0}, {0,-1} } 
    }
    for i=2,data.detectRange do
        table.insert(searchpattern,drawOctagon(i))
    end
    world.logInfo("Full searchpattern is %s",searchpattern)
    for k,v in pairs(searchpattern[1]) do
        world.logInfo("Key %s has val %s",k,v)
    end
end

function round(num)
-- to nearest integer
    return math.floor(num + 0.5)
end

function drawOctagon(i)
-- do stuff.  see the xcf file
    local perimeter = 4*math.ceil(i/2) + (3-i%2)*4*math.floor(i/2)
    local ret = {}
    world.logInfo("'Perimeter' of octagon %d is %d",i,perimeter)  
    
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
    world.logInfo("returning 'detect' in detect.lua:input()")
    return "detect"
  end
  if args.moves["special"] == 2 then
    world.logInfo("returning 'mousepos' in detect.lua:input()")
    soundDelay = soundDelay+1/100
    world.logInfo("Delay is now %d",soundDelay)
    --return "mousepos"
  end
  if args.moves["special"] == 3 then
    soundDelay = soundDelay-1/100
    world.logInfo("Delay is now %d",soundDelay)
  end
  
  return nil
end

function update(args)
  if args.actions["mousepos"] then
    local mpos = args.aimPosition
    world.logInfo("Mouse position is (%d,%d)",mpos[1],mpos[2])
  end
  
  if nextOreSound and os.clock() > nextOreSound then
    world.logInfo("Playing that sound...")
    nextOreSound = nil
    tech.playImmediateSound("/sfx/beep2.wav")
  end
  
  if (os.clock()-lastScan) > 0.1 then
    lastScan=os.clock()
    scan()
  end
  
  if args.actions["detect"] then
    world.logInfo("detect passed as an arg in detect.lua:update()")
    scan()
    return nil
  end
end

--function doDetect(candidates,resume,

function getCandidates()
    local c = {}
    local collisions = {}
    local origpos = tech.position()
    local n = 0
    local scanstartTime = os.clock()
    
    for i=-data.detectRange,data.detectRange do
        collisions = world.collisionBlocksAlongLine({origpos[1]+i,origpos[2]+data.detectRange},{origpos[1]+i,origpos[2]-data.detectRange})
        --[[for k,v in pairs(collisions) do
            c[v] = 1
            n = n + 1
            --world.logInfo("In detect.lua:getCandidates() Logging key %s val %s",k,v)
        end ]]--
    end
    world.logInfo("Found %d collisions in detect.lua:getCandidates(), total scan took %d ms",n,(os.clock()-scanstartTime)*1000)
    c = collisions
    return c
end
