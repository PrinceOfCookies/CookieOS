-- subterra_node_client.lua
-- Tiny reusable heartbeat/alert client for SubTerra nodes.

local nodeClient = {}

local config = {
  modemSide = "right",
  protocol = "subterra_core",
  heartbeatSeconds = 5,
  node = "unknown_node",
  role = "unknown",
  location = "unknown",
  services = {},
}

local function copyConfig(input)
  for key, value in pairs(input or {}) do
    config[key] = value
  end
end

function nodeClient.init(input)
  copyConfig(input)

  if peripheral.getType(config.modemSide) ~= "modem" then
    print("SubTerra node: no modem on " .. tostring(config.modemSide))
    return false
  end

  if not rednet.isOpen(config.modemSide) then
    rednet.open(config.modemSide)
  end

  return true
end

function nodeClient.send(packetType, data)
  local packet = data or {}

  packet.app = "subterra"
  packet.type = packetType
  packet.node = packet.node or config.node
  packet.role = packet.role or config.role
  packet.location = packet.location or config.location
  packet.services = packet.services or config.services

  rednet.broadcast(packet, config.protocol)
end

function nodeClient.heartbeat(status)
  nodeClient.send("heartbeat", {
    status = status or "online",
  })
end

function nodeClient.alert(message, level)
  nodeClient.send("alert", {
    message = message,
    level = level or "info",
  })
end

function nodeClient.heartbeatLoop()
  while true do
    nodeClient.heartbeat("online")
    sleep(config.heartbeatSeconds)
  end
end

return nodeClient
