-- CookieOS single-file installer. This file intentionally has no CookieOS dependencies.
local args = { ... }
local DEFAULT_REPOSITORY = "PrinceOfCookies/CookieOS"
local DEFAULT_REF = "cookieos-v3-rewrite"
local EMBEDDED_RELEASE_KEY = "COOKIEOS_RELEASE_KEY_NOT_CONFIGURED"
local EMBEDDED_MANIFEST = nil
local EMBEDDED_BUNDLE = nil
local INSTALL_ROOT = "/cookieos-install"
local CONFIG_PATH = "/cookieos-node.lua"

local band, bxor, bnot = bit32.band, bit32.bxor, bit32.bnot
local rrotate, rshift = bit32.rrotate, bit32.rshift
local constants = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function add(...)
  local value = 0
  for index = 1, select("#", ...) do value = band(value + select(index, ...), 0xffffffff) end
  return value
end
local function shaRaw(message)
  local bytes, bitLength = { message:byte(1, -1) }, #message * 8
  table.insert(bytes, 0x80)
  while #bytes % 64 ~= 56 do table.insert(bytes, 0) end
  local size = 2 ^ 32
  local high, low = math.floor(bitLength / size), bitLength % size
  for shift = 24, 0, -8 do table.insert(bytes, band(rshift(high, shift), 0xff)) end
  for shift = 24, 0, -8 do table.insert(bytes, band(rshift(low, shift), 0xff)) end
  local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset = 1, #bytes, 64 do
    local w = {}
    for index = 0, 15 do
      local at = offset + index * 4
      w[index] = add(bit32.lshift(bytes[at],24),bit32.lshift(bytes[at+1],16),bit32.lshift(bytes[at+2],8),bytes[at+3])
    end
    for index = 16, 63 do
      local x,y=w[index-15],w[index-2]
      w[index]=add(w[index-16],bxor(rrotate(x,7),rrotate(x,18),rshift(x,3)),w[index-7],bxor(rrotate(y,17),rrotate(y,19),rshift(y,10)))
    end
    local a,b,c,d,e,f,g,hh=table.unpack(h)
    for index=0,63 do
      local t1=add(hh,bxor(rrotate(e,6),rrotate(e,11),rrotate(e,25)),bxor(band(e,f),band(bnot(e),g)),constants[index+1],w[index])
      local t2=add(bxor(rrotate(a,2),rrotate(a,13),rrotate(a,22)),bxor(band(a,b),band(a,c),band(b,c)))
      hh,g,f,e,d,c,b,a=g,f,e,add(d,t1),c,b,a,add(t1,t2)
    end
    h={add(h[1],a),add(h[2],b),add(h[3],c),add(h[4],d),add(h[5],e),add(h[6],f),add(h[7],g),add(h[8],hh)}
  end
  local output={}
  for _,value in ipairs(h) do for shift=24,0,-8 do table.insert(output,string.char(band(rshift(value,shift),0xff))) end end
  return table.concat(output)
end
local function hex(value) return (value:gsub(".",function(byte)return string.format("%02x",byte:byte())end)) end
local function sha256(value) return hex(shaRaw(value)) end
local function hmac(key,message)
  if #key>64 then key=shaRaw(key) end
  key=key..string.rep("\0",64-#key)
  local inner,outer={},{}
  for index=1,64 do local byte=key:byte(index);inner[index]=string.char(bxor(byte,0x36));outer[index]=string.char(bxor(byte,0x5c)) end
  return hex(shaRaw(table.concat(outer)..shaRaw(table.concat(inner)..message)))
end
local function canonical(value, seen)
  seen=seen or {};local kind=type(value)
  if kind=="nil"then return"n"elseif kind=="boolean"then return value and"b1"or"b0"elseif kind=="number"then return"d"..string.format("%.17g",value)..";"elseif kind=="string"then return"s"..#value..":"..value end
  if kind~="table"or seen[value]then error("Unsupported manifest value")end
  seen[value]=true;local keys={};for key in pairs(value)do table.insert(keys,key)end
  table.sort(keys,function(a,b)return type(a)..":"..tostring(a)<type(b)..":"..tostring(b)end)
  local parts={"t",tostring(#keys),":"};for _,key in ipairs(keys)do table.insert(parts,canonical(key,seen));table.insert(parts,canonical(value[key],seen))end
  seen[value]=nil;return table.concat(parts)
end
local function unsignedManifest(manifest)
  local result={};for key,value in pairs(manifest)do if key~="signature"then result[key]=value end end;return result
end

local function option(name)
  for index,value in ipairs(args)do if value==name then return args[index+1]or true end end
end
local function flag(name)for _,value in ipairs(args)do if value==name then return true end end return false end
local function ask(prompt,default)
  write(prompt..(default and(" ["..default.."]")or"")..": ");local value=read();if value==""then return default end;return value
end
local function yes(prompt,default)
  write(prompt..(default and" [Y/n] "or" [y/N] "));local value=read():lower();if value==""then return default end;return value=="y"or value=="yes"
end
local function choose(prompt,choices,default)
  print(prompt);for index,choice in ipairs(choices)do print(index..". "..choice)end
  while true do local value=tonumber(ask("Select",tostring(default or 1)));if value and choices[value]then return value end end
end
local function writeFile(path,contents)
  local directory=fs.getDir(path);if directory~=""and not fs.exists(directory)then fs.makeDir(directory)end
  local handle=assert(fs.open(path,"wb")or fs.open(path,"w"));handle.write(contents);handle.close()
end
local function readFile(path)
  local handle=fs.open(path,"rb")or fs.open(path,"r");if not handle then return nil end
  local value=handle.readAll();handle.close();return value
end
local function runProgram(path,...)
  if shell and type(shell.run)=="function"then return shell.run(path,...)end
  if type(os.run)=="function"then return os.run(_ENV,path,...)end
  error("Cannot launch "..path..": no shell or os.run API")
end
local function urlEncode(value)
  return(tostring(value):gsub("([^%w%-_%.~])",function(character)return string.format("%%%02X",character:byte())end))
end
local function urlEncodePath(path)
  local parts={};for part in tostring(path):gmatch("[^/]+")do parts[#parts+1]=urlEncode(part)end;return table.concat(parts,"/")
end
local function readHttpResponse(response,label)
  local code;if response.getResponseCode then local ok,value=pcall(response.getResponseCode);if ok then code=value end end
  local ok,body=pcall(response.readAll);pcall(response.close)
  if not ok then return nil,"Could not read "..label..": "..tostring(body)end
  return body,nil,code
end
local function fetchHttpFile(url)
  local response,requestError,errorResponse=http.get(url,{["User-Agent"]="CookieOS"});response=response or errorResponse
  if not response then return nil,"HTTP request failed: "..tostring(requestError)end
  local body,readError,code=readHttpResponse(response,"HTTP response")
  if not body then return nil,readError end
  if code and code>=400 then return nil,"HTTP request failed with status "..code end
  return body
end
local function decodeBase64(value)
  value=value:gsub("%s","");if type(textutils.decodeBase64)=="function"then return textutils.decodeBase64(value)end
  if#value%4~=0 then error("invalid base64 length")end
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local lookup={}
  for index=1,#alphabet do lookup[alphabet:sub(index,index)]=index-1 end
  local output={};for offset=1,#value,4 do
    local a,b,c,d=value:sub(offset,offset),value:sub(offset+1,offset+1),value:sub(offset+2,offset+2),value:sub(offset+3,offset+3)
    if not lookup[a]or not lookup[b]or(c~="="and not lookup[c])or(d~="="and not lookup[d])or(c=="="and d~="=")then error("invalid base64 data")end
    if(c=="="or d=="=")and offset+3~=#value then error("invalid base64 padding")end
    local combined=lookup[a]*262144+lookup[b]*4096+(lookup[c]or 0)*64+(lookup[d]or 0)
    output[#output+1]=string.char(math.floor(combined/65536)%256)
    if c~="="then output[#output+1]=string.char(math.floor(combined/256)%256)end
    if d~="="then output[#output+1]=string.char(combined%256)end
    if offset%32768==1 and os.queueEvent and os.pullEvent then os.queueEvent("cookieos_installer_yield");os.pullEvent("cookieos_installer_yield")end
  end;return table.concat(output)
end
local function fetchGitHubFile(path,ref,repository)
  repository=repository or DEFAULT_REPOSITORY;ref=ref or DEFAULT_REF
  local url="https://api.github.com/repos/"..repository.."/contents/"..urlEncodePath(path).."?ref="..urlEncode(ref)
  local headers={["User-Agent"]="CookieOS",["Accept"]="application/vnd.github+json",["X-GitHub-Api-Version"]="2022-11-28"}
  local response,requestError,errorResponse=http.get(url,headers);response=response or errorResponse
  if not response then return nil,"GitHub API request failed: "..tostring(requestError)end
  local body,readError,code=readHttpResponse(response,"GitHub API response")
  if not body then return nil,readError end
  local ok,payload=pcall(textutils.unserializeJSON,body)
  if not ok or type(payload)~="table"then return nil,"GitHub API returned invalid JSON"..(code and(" (HTTP "..code..")")or"")end
  if code and code>=400 then return nil,"GitHub API error "..code..": "..tostring(payload.message or"unknown error")end
  if payload.message and not payload.content then return nil,"GitHub API error: "..tostring(payload.message)end
  if payload.encoding~="base64"or type(payload.content)~="string"then return nil,"GitHub API response did not contain base64 file content"end
  local decodedOk,contents=pcall(decodeBase64,payload.content)
  if not decodedOk or type(contents)~="string"then return nil,"GitHub API returned invalid base64 content: "..tostring(contents)end
  return contents
end
local function safePath(path)
  return type(path)=="string"and path:sub(1,1)=="/"and not path:find("..",1,true)
    and path~=CONFIG_PATH and not path:find("^/cookieos%-data/")and not path:find("^/cookieos%-install/")
end
local function detect()
  local found={};for _,name in ipairs(peripheral.getNames())do local kind=peripheral.getType(name);found[kind]=found[kind]or{};table.insert(found[kind],name)end
  print("Detected peripherals:");if next(found)==nil then print("  none")end
  for kind,names in pairs(found)do print("  "..kind..": "..table.concat(names,", "))end
  return found
end
local presets={
  {name="Auth terminal",mode="client",services={"node","fleet-agent","terminal"}},
  {name="Command Authority",mode="server",services={"node","fleet-agent","command-authority","command-terminal"},requires={"speaker","playerDetector"}},
  {name="Auth/core server",mode="server",services={"node","fleet-agent","auth","audit","events","personnel","security","maintenance","operations","orchestration","terminal"}},
  {name="Player tracker",mode="server",services={"node","fleet-agent","player-tracker","maintenance"},requires="player_detector"},
  {name="Speaker zone",mode="server",services={"node","fleet-agent","audio","maintenance"},requires="speaker"},
  {name="Chat gateway",mode="server",services={"node","fleet-agent","chat","maintenance"},requires="chatBox"},
  {name="Access controller",mode="server",services={"node","fleet-agent","operations","maintenance"}},
  {name="Relay",mode="relay",services={"node","fleet-agent"}},
  {name="Hybrid core + relay",mode="hybrid",services={"node","fleet-agent","auth","audit","events","personnel","security","maintenance","operations","orchestration","terminal"}},
  {name="Custom node",mode="client",services={"node"}},
}
local function randomKey(node)return sha256(node..":"..os.epoch("utc")..":"..math.random()..":"..math.random())end
local function wizard(roleName,existing)
  local found=detect();local selected
  if roleName then for _,preset in ipairs(presets)do if preset.name:lower():find(roleName:lower(),1,true)then selected=preset end end end
  if not selected then selected=presets[choose("Choose this computer's role:",(function()local names={}for _,p in ipairs(presets)do table.insert(names,p.name)end return names end)())]end
  if selected.requires then for _,required in ipairs(type(selected.requires)=="table"and selected.requires or{selected.requires})do
    if not found[required]and not(required=="playerDetector"and found.player_detector)then printError("Warning: role requires "..required)end
  end end
  local node=ask("Unique node name",existing and existing.node or("cookieos-"..os.getComputerID()))
  local location=ask("Facility location",existing and existing.location or"Unknown")
  local modemNames=found.modem or{}
  local sides={};for _,name in ipairs(modemNames)do table.insert(sides,name)end
  if #sides==0 then table.insert(sides,ask("Modem side","back"))end
  local transports={};for index,side in ipairs(sides)do table.insert(transports,{name="link-"..index,side=side,type="modem"})end
  if selected.name=="Custom node"then
    local entered=ask("Service names (comma separated)","node,terminal");selected.services={}
    for name in entered:gmatch("[^,%s]+")do table.insert(selected.services,name)end
    selected.mode=ask("Node mode: client/server/relay/hybrid","client")
  end
  local config={version=3,node=node,mode=selected.mode,location=location,identity={nodeKey=existing and existing.identity and existing.identity.nodeKey or randomKey(node)},transports=transports,services=selected.services}
  if existing then
    config.network=existing.network;config.update=existing.update;config.auth=existing.auth
    config.pairing=existing.pairing;config.events=existing.events;config.commandAuthority=existing.commandAuthority
    if existing.identity and existing.identity.user then config.identity.user=existing.identity.user end
  end
  local isAuthority=selected.name=="Auth/core server"or selected.name=="Hybrid core + relay"
  local isCommand=selected.name=="Command Authority"
  local isAccess=selected.name=="Access controller"
  if isCommand then
    local user=ask("CL6 Minecraft username")
    local password,override="",""
    while #password<8 do write("CL6 password (8+ characters): ");password=read("*")end
    while #override<8 or override==password do
      write("Different emergency override password (8+ characters): ");override=read("*")
      if override==password then printError("Override password must differ from the normal password")end
    end
    local function credential(secret,label)
      local salt=sha256(node..":"..label..":"..os.epoch("utc")..":"..math.random())
      local value=salt..":"..secret;for _=1,64 do value=sha256(value..":"..salt)end
      return{salt=salt,rounds=64,hash=value}
    end
    local position
    if gps and gps.locate then local x,y,z=gps.locate(2,false);if x then position={x=x,y=y,z=z}end end
    if not position then
      print("GPS location unavailable; enter this computer's coordinates.")
      position={x=tonumber(ask("X")),y=tonumber(ask("Y")),z=tonumber(ask("Z"))}
      if not position.x or not position.y or not position.z then error("Valid Command Authority coordinates are required")end
    end
    config.commandAuthority={authority=true,user=user,radius=tonumber(ask("Physical access radius","6"))or 6,debug=true,
      position=position,credential=credential(password,"normal"),overrideCredential=credential(override,"override")}
    local peers=ask("Backup Command Authority nodes (comma separated, optional)","")
    config.commandCluster={peers={},quorum=1,priority=tonumber(ask("Authority priority (higher wins)","100"))or 100}
    for peer in peers:gmatch("[^,%s]+")do table.insert(config.commandCluster.peers,peer)end
    if #config.commandCluster.peers>0 then config.commandCluster.quorum=tonumber(ask("Required authority quorum","1"))or 1 end
  elseif isAuthority then
    if not config.auth then
      local admin=ask("Initial administrator","admin")
      local password="";while #password<4 do write("Initial administrator password (4+ characters): ");password=read("*")end
      config.auth={seedUsers={[admin]={clearance=5,role="Administrator",status="Active",extraPermissions={"all"},password=password}},delegates={}}
    end
    config.events=config.events or{publishers={}}
    config.commandAuthority=config.commandAuthority or{required=true,node=ask("Primary Command Authority node name","cookiesecurity-command")}
    local peers=ask("Backup Command Authority nodes (comma separated, optional)","");config.commandAuthority.peers={}
    for peer in peers:gmatch("[^,%s]+")do table.insert(config.commandAuthority.peers,peer)end
    if #config.commandAuthority.peers>0 then config.commandAuthority.quorum=tonumber(ask("Required authority quorum","1"))or 1 end
  else
    config.identity.user=ask("Default username (login can override)","admin")
    config.commandAuthority=config.commandAuthority or{required=true,node=ask("Primary Command Authority node name","cookiesecurity-command")}
  end
  if isAccess then
    config.operations={doors={}}
    print("Configure redstone doors. Leave the door id blank when finished.")
    while true do
      local id=ask("Door id","");if id==""then break end
      table.insert(config.operations.doors,{id=id,zone=ask("Door zone","default"),side=ask("Redstone side","back"),clearance=tonumber(ask("Required clearance 0-5","1"))or 1,locked=true})
    end
  end
  if found.monitor and isAuthority and yes("Enable personnel monitor display?",false)then
    table.insert(config.services,"personnel-display");config.personnelDisplay={side=found.monitor[1],textScale=0.5}
  end
  if isAuthority then
    local modules=ask("Extension modules (comma separated, optional)","");config.extensions={modules={}}
    for moduleName in modules:gmatch("[^,%s]+")do table.insert(config.extensions.modules,moduleName)end
  end
  if not isCommand and flag("--reconfigure")then config.pairing=nil end
  return config
end
local function saveConfig(config)
  if fs.exists(CONFIG_PATH)then if fs.exists(CONFIG_PATH..".bak")then fs.delete(CONFIG_PATH..".bak")end;fs.copy(CONFIG_PATH,CONFIG_PATH..".bak")end
  writeFile(CONFIG_PATH,"return "..textutils.serialize(config))
end
local function loadManifest()
  local offline=option("--offline")
  if offline then
    local root=offline==true and"disk"or offline
    local raw=readFile(fs.combine(root,"manifest.json"));if not raw then error("Offline manifest not found")end
    return assert(textutils.unserializeJSON(raw)),function(file)return readFile(fs.combine(root,"packages",file.path:sub(2)))end
  end
  if not http then error("HTTP is disabled; use --offline <disk path>")end
  local version=option("--version")
  local manifestUrl=option("--manifest");local manifestRaw,manifestError
  local embeddedBundle
  if not manifestUrl and not version and EMBEDDED_MANIFEST then
    local manifestOk;manifestOk,manifestRaw=pcall(decodeBase64,EMBEDDED_MANIFEST);if not manifestOk then error("Embedded manifest is invalid")end
    local bundleOk,bundleRaw=pcall(decodeBase64,EMBEDDED_BUNDLE or"");if not bundleOk then error("Embedded bundle is invalid")end
    embeddedBundle=textutils.unserializeJSON(bundleRaw);if type(embeddedBundle)~="table"or type(embeddedBundle.files)~="table"then error("Embedded bundle is invalid")end
  elseif manifestUrl then manifestRaw,manifestError=fetchHttpFile(manifestUrl)
  else manifestRaw,manifestError=fetchGitHubFile("release/manifest.json",version or DEFAULT_REF,DEFAULT_REPOSITORY)end
  if not manifestRaw then error("Manifest download failed: "..tostring(manifestError))end
  local manifest=textutils.unserializeJSON(manifestRaw);if type(manifest)~="table"then error("Invalid manifest JSON")end
  local repository=manifest.repository or DEFAULT_REPOSITORY;local ref=version or manifest.ref or DEFAULT_REF
  local bundle=embeddedBundle
  if not bundle and type(manifest.bundle)=="string"then
    local bundleRaw,bundleError=fetchGitHubFile(manifest.bundle,ref,repository)
    if not bundleRaw then error("Release bundle download failed: "..tostring(bundleError))end
    bundle=textutils.unserializeJSON(bundleRaw);if type(bundle)~="table"or type(bundle.files)~="table"then error("Invalid release bundle")end
  end
  return manifest,function(file)
    if bundle then local contents=bundle.files[file.source];if type(contents)~="string"then return nil,"File missing from release bundle: "..tostring(file.source)end;return contents end
    if type(file.source)=="string"then return fetchGitHubFile(file.source,ref,repository)end
    if type(file.url)=="string"then return fetchHttpFile(file.url)end
    return nil,"Manifest entry has no source"
  end
end
local function verifyManifest(manifest)
  if type(manifest)~="table"or type(manifest.files)~="table"or type(manifest.version)~="string"then error("Invalid release manifest")end
  local key=option("--key")or(EMBEDDED_RELEASE_KEY~="COOKIEOS_RELEASE_KEY_NOT_CONFIGURED"and EMBEDDED_RELEASE_KEY)
  if key then if hmac(key,canonical(unsignedManifest(manifest)))~=manifest.signature then error("Release signature invalid")end
  elseif not yes("Installer has no pinned release key. Continue with file-hash verification only?",false)then error("Installation cancelled")end
  for _,file in ipairs(manifest.files)do
    if not safePath(file.path)or type(file.sha256)~="string"then error("Unsafe manifest path")end
    if file.source~=nil and(type(file.source)~="string"or file.source:sub(1,1)=="/"or file.source:find("..",1,true))then error("Unsafe manifest source")end
    if type(file.source)~="string"and type(file.url)~="string"then error("Manifest entry has no source")end
  end
  local packagedPaths={};for _,file in ipairs(manifest.files)do packagedPaths[file.path]=true end
  if type(manifest.remove)~="nil"and type(manifest.remove)~="table"then error("Invalid obsolete path list")end
  for _,path in ipairs(manifest.remove or{})do if not safePath(path)or packagedPaths[path]then error("Unsafe obsolete path")end end
  return key
end
local function stage(manifest,fetch)
  local stage=INSTALL_ROOT.."/staged";if fs.exists(stage)then fs.delete(stage)end;fs.makeDir(stage)
  for index,file in ipairs(manifest.files)do
    write("["..index.."/"..#manifest.files.."] "..file.path.." ")
    local contents,err=fetch(file);if not contents then error("Download failed: "..tostring(err))end
    if sha256(contents)~=file.sha256 then error("Hash mismatch: "..file.path)end
    writeFile(fs.combine(stage,file.path:sub(2)),contents);print("ok")
    if os.queueEvent and os.pullEvent then os.queueEvent("cookieos_installer_yield");os.pullEvent("cookieos_installer_yield")end
  end
end
local function apply(manifest)
  local stage,backup=INSTALL_ROOT.."/staged",INSTALL_ROOT.."/backup"
  if fs.exists(backup)then fs.delete(backup)end;fs.makeDir(backup)
  local completed={}
  local ok,err=pcall(function()
    for _,file in ipairs(manifest.files)do
      local target=file.path;local old=fs.combine(backup,target:sub(2));local staged=fs.combine(stage,target:sub(2))
      if fs.exists(target)then local dir=fs.getDir(old);if dir~=""and not fs.exists(dir)then fs.makeDir(dir)end;fs.copy(target,old)end
      table.insert(completed,target);if fs.exists(target)then fs.delete(target)end;local dir=fs.getDir(target);if dir~=""and not fs.exists(dir)then fs.makeDir(dir)end;fs.copy(staged,target)
    end
    for _,target in ipairs(manifest.remove or{})do
      local old=fs.combine(backup,target:sub(2));if fs.exists(target)then local dir=fs.getDir(old);if dir~=""and not fs.exists(dir)then fs.makeDir(dir)end;fs.copy(target,old);table.insert(completed,target);fs.delete(target)end
    end
  end)
  if not ok then
    for _,target in ipairs(completed)do local old=fs.combine(backup,target:sub(2));if fs.exists(target)then fs.delete(target)end;if fs.exists(old)then fs.copy(old,target)end end
    error("Install failed and was rolled back: "..tostring(err))
  end
  writeFile(INSTALL_ROOT.."/installed.db",textutils.serialize({version=manifest.version,files=manifest.files,remove=manifest.remove,installedAt=os.epoch("utc")}))
end
local function installStartup()
  if fs.exists("/startup.lua")and not fs.exists("/startup.lua.cookieos.bak")then fs.copy("/startup.lua","/startup.lua.cookieos.bak")end
  writeFile("/startup.lua",'shell.run("startup-v3.lua")\n')
end
local function uninstall()
  local raw=readFile(INSTALL_ROOT.."/installed.db");local state=raw and textutils.unserialize(raw)
  if not state or type(state.files)~="table"then error("Install record not found")end
  if not yes("Remove CookieOS program files?",false)then return end
  for _,file in ipairs(state.files)do if safePath(file.path)and fs.exists(file.path)then fs.delete(file.path)end end
  if fs.exists("/startup.lua.cookieos.bak")then if fs.exists("/startup.lua")then fs.delete("/startup.lua")end;fs.move("/startup.lua.cookieos.bak","/startup.lua")
  elseif fs.exists("/startup.lua")then fs.delete("/startup.lua")end
  if yes("Also remove configuration?",false)and fs.exists(CONFIG_PATH)then fs.delete(CONFIG_PATH)end
  if yes("Also remove CookieOS data? This cannot be undone.",false)and fs.exists("/cookieos-data")then fs.delete("/cookieos-data")end
  print("CookieOS uninstalled.")
end

if flag("--self-test")then
  assert(sha256("abc")=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  assert(hmac("key","The quick brown fox jumps over the lazy dog")=="f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
  print("Installer cryptographic self-test passed.");return
end
if flag("--recovery")then
  if not fs.exists("/recovery.lua")then error("Recovery environment is not installed")end
  runProgram("/recovery.lua");return
end
if flag("--uninstall")then uninstall();return end
print("CookieOS Installer")
print("Computer "..os.getComputerID().." | ".._HOST)
local freeSpace=fs.getFreeSpace("/");if type(freeSpace)=="number"and freeSpace<100000 then printError("Warning: less than 100 KB free")end
local existing
if fs.exists(CONFIG_PATH)then local chunk=loadfile(CONFIG_PATH);if chunk then local loadedOk,value=pcall(chunk);if loadedOk and type(value)=="table"then existing=value end end end
local config
if (flag("--upgrade")or flag("--repair"))and existing then config=existing
else config=wizard(option("--role"),existing)end
if (flag("--upgrade")or flag("--repair"))and not config.commandAuthority then
  error("This pre-Command CookieSecurity configuration must be migrated with install.lua --reconfigure before upgrade")
end
if flag("--reconfigure")then
  saveConfig(config)
  if config.commandAuthority and config.commandAuthority.required then
    print("Command Authority enrollment is required before this node can boot.");runProgram("/pair-node.lua")
    for _,peer in ipairs(config.commandAuthority.peers or{})do print("Now generate a code on backup authority "..peer..".");runProgram("/pair-node.lua","/cookieos-node.lua",config.transports[1].side,peer)end
  end
  print("Configuration updated. Reboot to apply.");return
end
local manifest,fetch=loadManifest();local releaseKey=verifyManifest(manifest)
if releaseKey then config.update={signingKey=releaseKey}end
print("Installing CookieOS "..manifest.version);stage(manifest,fetch);apply(manifest);saveConfig(config);installStartup()
print("Installation complete for node "..config.node..".")
if config.commandAuthority and config.commandAuthority.required then
  print("Command Authority enrollment is required before this node can boot.");runProgram("/pair-node.lua")
  for _,peer in ipairs(config.commandAuthority.peers or{})do print("Now generate a code on backup authority "..peer..".");runProgram("/pair-node.lua","/cookieos-node.lua",config.transports[1].side,peer)end
end
if yes("Reboot now?",true)then os.reboot()end
