local socket =  require("socket.core")

local FLOW_CONTROL_OPTION = {NONE=0,["ONE-TO-ONE"]=1}
local GAME_MODE = {NORMAL=0}

local isClient = false
local host = "0.0.0.0"
local relay = nil
local port = 7777
local gameMode = GAME_MODE.NORMAL
local flowControl = 0
local relayConnected = false
local speedReset = 1
local store43 = 0

if arg == nil then arg = io.read() end

local argWords = {}
for word in arg:gmatch("([^%s]+)") do table.insert(argWords, word) end
local i = 1
while i <= #argWords do
	local word = argWords[i]
	if word == "--relay" then
		i = i+1
		relay = argWords[i]
		isClient = relay ~= "host"
	elseif word == "--port" then
		i = i+1
		port = tonumber(argWords[i])
	elseif word == "--flow-control" then
		i = i+1
		flowControl = FLOW_CONTROL_OPTION[argWords[i]] ~= nil and FLOW_CONTROL_OPTION[argWords[i]] or 0
	else
		host = word
		isClient = relay ~= "host"
	end
	i = i+1
end

-- erase all traces of our temporary variables
argWord = nil
i = nil
word = nil

local function getReadAddress(address)
	if isClient then 
		return address+0x80
	else
		return address
	end
end

local function getWriteAddress(address)
	if isClient then
		return address
	else
		return address+0x80
	end
end

local function getLevelDataReadAddress(address)
	if isClient then 
		return address+0x100
	else
		return address
	end
end

local function getLevelDataWriteAddress(address)
	if isClient then
		return address
	else
		return address+0x100
	end
end

local dataSocket = nil
local send = true

local requestStart = 0
local startRequested = 0
local startSeed = {string.char(0x00),string.char(0x00) }

local requestContinue = 0
local continueRequested = 0

local _current = string.char(0x03)..string.char(0x0F)..string.char(0x00)
local _speed = 0
local _level = 0
local _state = 0
local _lost = 0

local remoteCurrent = nil
local remoteGameState = 0

local keyFramesIn = {}
local keyFramesOut = {}

local requestLoss = 0
local lossRequested = 0

local sendGreeting = false

local sendInit = false
local initSent = false

local function insertKeyFrame(messages, index)
	type = messages:sub(index):byte()
	if type == 0 then
		table.insert(keyFramesIn,messages:sub(index,index))
		return index+1
	elseif type == 1 then
		table.insert(keyFramesIn,messages:sub(index,index+3))
		return index+4
	else
		table.insert(keyFramesIn,messages:sub(index,index+type+1))
		return index+type+2
	end
end

local MESSAGE = {
	SET_GAME_STATE = 0,
	SET_CURRENT_POS = 1,
	GREETING = 2,
	REQUEST_START = 3,
	REQUEST_CONTINUE = 4,
	SET_SPEED = 5,
	SET_LEVEL = 6,
	ADD_KEYFRAME = 7,
	INIT = 8,
	REQUEST_LOSS = 9
}

local function consumeMessage(messages, index)
	messageType = messages:sub(index,index):byte()
	if messageType == MESSAGE.SET_GAME_STATE then	
		remoteGameState = messages:sub(index+1,index+1):byte()
		return index+2
	elseif messageType == MESSAGE.SET_CURRENT_POS then
		remoteCurrent = messages:sub(index+1,index+3)
		return index+4
	elseif messageType == MESSAGE.REQUEST_START then
		startRequested = 1
		startSeed = {messages:sub(index+1,index+1):byte(), messages:sub(index+2,index+2):byte()}
		return index+3
	elseif messageType == MESSAGE.REQUEST_CONTINUE then
		continueRequested = 1
		return index+1
	elseif messageType == MESSAGE.SET_SPEED then
		memory.writebyte(getWriteAddress(0x030B), messages:sub(index+1,index+1):byte());
		return index+2
	elseif messageType == MESSAGE.SET_LEVEL then
		memory.writebyte(getWriteAddress(0x0316), messages:sub(index+1,index+1):byte());
		return index+2
	elseif messageType == MESSAGE.ADD_KEYFRAME then
		return insertKeyFrame(messages,index+1)
	elseif messageType == MESSAGE.REQUEST_LOSS then
		lossRequested = 1
		return index+1
	elseif messageType == MESSAGE.INIT then
		if isClient then
			flowControl = messages:sub(index+1,index+1):byte()
			gameMode = messages:sub(index+2,index+2):byte()
		end
		if not initSent then
			sendInit = true
		end
		emu.message("Initialized")
		return index+3
	elseif messageType == MESSAGE.GREETING then
		sendInit = true
		return index+1
	end
end

local function consumeMessages(messages)
	if messages ~= nil and string.len(messages) > 0 then
		index = 1
		while index <= string.len(messages) do
			index = consumeMessage(messages,index)
		end
	end
end

local function buildMessages() 
	dataOut = ""
	current = string.char(memory.readbyte(getReadAddress(0x305)))..string.char(memory.readbyte(getReadAddress(0x306)))..string.char(memory.readbyte(getReadAddress(0x325)))
	if current ~= _current then
		dataOut = dataOut..string.char(MESSAGE.SET_CURRENT_POS)..current
		_current = current
	end
	speed = memory.readbyte(getReadAddress(0x030B))
	if speed ~= _speed or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_SPEED)..string.char(speed)
		_speed = speed
	end
	level = memory.readbyte(getReadAddress(0x0316))
	if level ~= _level or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_LEVEL)..string.char(level)
		_level = level
	end
	state = memory.readbyte(0x0046)
	if state ~= _state  or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_GAME_STATE)..string.char(state)
		_state = state
	end
	if requestStart == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_START)..table.concat(startSeed)
		requestStart = 0
	end
	if requestContinue == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_CONTINUE)
		requestContinue = 0
	end
	while #keyFramesOut > 0 do
		keyFrameOut = table.remove(keyFramesOut,1)
		dataOut = dataOut..string.char(MESSAGE.ADD_KEYFRAME)..keyFrameOut
	end
	if requestLoss == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_LOSS)
		requestLoss = 0
	end
	if sendInit == true then
		dataOut = dataOut..string.char(MESSAGE.INIT)..string.char(flowControl)..string.char(gameMode)
		initSent = true
		sendInit = false
	end
	if (sendGreeting) then
		dataOut = dataOut..string.char(MESSAGE.GREETING)
		sendGreeting = false
	end
	return dataOut
end

local function handleInput() 
	if isClient then
		local state = memory.readbyte(0x46)
		if state == 1 then
			if memory.readbyte(0x65) < 2 then
				p1Input = memory.readbyte(0xF5)
				leftRight = p1Input % 4
				memory.writebyte(0xF6,leftRight)
				memory.writebyte(0xF5,p1Input-leftRight)
			end
		elseif state > 1 then
			p1Input = memory.readbyte(0xF5)
			dPad= p1Input % 0x10
			startSelect = (p1Input % 32) - dPad
			memory.writebyte(0xF6,p1Input-startSelect)
			if memory.readbyte(0x45) ~= 0xBF then
				memory.writebyte(0xF5,startSelect)
			else
				memory.writebyte(0xF5,0)
			end
		end
	elseif memory.readbyte(0x45) == 0xBF then
		p1Input = memory.readbyte(0xF5)
		dPad= p1Input % 0x10
		startSelect = (p1Input % 32) - dPad
		memory.writebyte(0xF5,p1Input-startSelect)
	end
end

local function handleStart1() 
	if isClient and startRequested == 1 then
		memory.writebyte(0xF5,0x10)	
	end
end

local function handleStart() 
	if not isClient and remoteGameState == 0x01 then
		if memory.readbyte(0x46) == 0x02 then
			requestStart = 1
			startSeed = {string.char(memory.readbyte(0x17)),string.char(memory.readbyte(0x18)) }
		end
	elseif startRequested == 1 and startSeed ~= nil then
		memory.writebyte(0x46,0x02)	
		memory.writebyte(0x17,startSeed[1])	
		memory.writebyte(0x18,startSeed[2])
		startRequested = 0
	elseif memory.readbyte(0x46) == 0x02 then
		memory.writebyte(0x46,0x01)	
	end
end


local function handleContinueOLD() 
	if not isClient then
		if memory.readbyte(0xF5)%0x20 > 0xF or memory.readbyte(0xF7)%0x20 > 0xF then
            requestContinue = 1
		end
	else 
		if continueRequested == 1 then
			memory.writebyte(0xF5,0x10)	
			continueRequested = 0	
		else
			memory.writebyte(0xF5,0x00)	
			memory.writebyte(0xF7,0x00)	
		end
	end
end

local function handleContinue() 
	if isClient then
		if continueRequested == 1 then
			memory.writebyte(0xF5,0x10)	
			continueRequested = 0	
		else
			memory.writebyte(0xF5,0x00)	
			memory.writebyte(0xF7,0x00)	
		end
	end
end

local function handleContinue2() 
	if not isClient then
		requestContinue = 1
	end
end

local function collectGarbage2() 
	if gameMode == GAME_MODE.NORMAL and memory.readbyte(0x58) == (isClient and 5 or 4) then
		table.insert(keyFramesOut,string.char(2)..string.char(memory.readbyte(0x43)%4)..string.char(memory.readbyte(getWriteAddress(0x329)))..string.char(memory.readbyte(getWriteAddress(0x32A))))
	end
end
	
local function collectGarbage3() 
	if gameMode == GAME_MODE.NORMAL and memory.readbyte(0x58) == (isClient and 5 or 4) then
		table.insert(keyFramesOut,string.char(3)..string.char(memory.readbyte(0x43)%4)..string.char(memory.readbyte(getWriteAddress(0x329)))..string.char(memory.readbyte(getWriteAddress(0x32A)))..string.char(memory.readbyte(getWriteAddress(0x32B))))
	end
end

local function collectGarbage4() 
	if gameMode == GAME_MODE.NORMAL and memory.readbyte(0x58) == (isClient and 5 or 4)  then
		table.insert(keyFramesOut,string.char(4)..string.char(memory.readbyte(0x43)%2)..string.char(memory.readbyte(getWriteAddress(0x329)))..string.char(memory.readbyte(getWriteAddress(0x32A)))..string.char(memory.readbyte(getWriteAddress(0x32B)))..string.char(memory.readbyte(getWriteAddress(0x32C))))
	end
end

local function waitForNext1()
	if memory.readbyte(0x58) == (isClient and 4 or 5) then
		store43 = memory.readbyte(0x43)
		if #keyFramesIn == 0 then
			memory.setregister('a',0x01)	
		end
	end
end

local function waitForNext2()
	if memory.readbyte(0x58) == (isClient and 4 or 5) then
		if #keyFramesIn == 0 then
			memory.setregister('a',0x02)	
		end
		memory.writebyte(0x43,store43)
	else
		
	end
	
end

local function preventGarbage()
	if memory.readbyte(0x58) == (isClient and 5 or 4) then
		memory.writebyte(0x98,0x00)
	end
end

local function processNext()
	if 	memory.readbyte(0x58) == (isClient and 4 or 5) then
		if #keyFramesIn > 0 then 
			garbageIn = table.remove(keyFramesIn,1)
			if garbageIn:sub(1,1):byte() > 1 then
				garbageCount = garbageIn:sub(1,1):byte()
				firstGarbage = garbageIn:sub(2,2):byte()
				memory.writebyte(getReadAddress(0x318),garbageCount);
				memory.writebyte(0x43,firstGarbage);
				memory.writebyte(getReadAddress(0x329),garbageIn:sub(3,3):byte())
				if garbageCount == 2 then
					memory.writebyte(getReadAddress(0x32A),garbageIn:sub(4,4):byte())
				else
					memory.writebyte(getReadAddress(0x32A),garbageIn:sub(4,4):byte())
					memory.writebyte(getReadAddress(0x32B),garbageIn:sub(5,5):byte())
					if garbageCount > 3 then
						memory.writebyte(getReadAddress(0x32C),garbageIn:sub(6,6):byte())
					end
				end
			end
		end
	elseif memory.readbyte(getWriteAddress(0x318)) == 0 then 
		table.insert(keyFramesOut, string.char(0))
	end
end

local function landPill()
	if memory.readbyte(0x58) == (isClient and 5 or 4) then
		table.insert(keyFramesOut, string.char(1)..string.char(memory.readbyte(getReadAddress(0x305)))..string.char(memory.readbyte(getReadAddress(0x306)))..string.char(memory.readbyte(getReadAddress(0x325))))
	end
end

if memory.readbyte(0xFFF0) == 0x2D then 
	memory.registerexec(0x815B,handleStart)
	memory.registerexec(0x99F9,handleStart1)
	memory.registerexec(0x9675,handleContinue)
	memory.registerexec(0xB31A,handleContinue)
	memory.registerexec(0xB7E7,handleInput)	
	memory.registerexec(0xB7F5,handleInput)
	memory.registerexec(0x9C30,collectGarbage2)
	memory.registerexec(0x9C4E,collectGarbage3)
	memory.registerexec(0x9C6D,collectGarbage4)
	memory.registerexec(0x9BF1,waitForNext1)
	memory.registerexec(0x9C00,waitForNext2)
	memory.registerexec(0x9C25,processNext)
	memory.registerexec(0x9C0E,preventGarbage)
else
	memory.registerexec(0x814B,handleStart)
	memory.registerexec(0x99DF,handleStart1)
	memory.registerexec(0x9665,handleContinue)
	memory.registerexec(0x966B,handleContinue2)
	memory.registerexec(0xB300,handleContinue)
	memory.registerexec(0xB308,handleContinue2)
	memory.registerexec(0xB7CD,handleInput)
	memory.registerexec(0xB7DB,handleInput)
	memory.registerexec(0x9C16,collectGarbage2)
	memory.registerexec(0x9C34,collectGarbage3)
	memory.registerexec(0x9C55,collectGarbage4)
	memory.registerexec(0x9BD7,waitForNext1)
	memory.registerexec(0x9BE6,waitForNext2)
	memory.registerexec(0x9C0B,processNext)
	memory.registerexec(0x9BF4,preventGarbage)
	memory.registerexec(0x8DB9,landPill)
end


local doExit = false

local function comm(r)
	local dataCount = 0 
	local data = nil
	local send = true
	while true do
		if dataSocket == nil then
			if isClient or relay ~= nil then
				dataSocket = socket.tcp()
				if not dataSocket:connect(host,port) then
					dataSocket = nil
					doExit = true
				else 
					if relay ~= nil then
						dataSocket:setoption('tcp-nodelay',true)
						dataSocket:send(relay)
					end 
				end
			else
				if server == nil then 
					server = socket.tcp()
					server:bind(host,port)
					server:listen()
				end
				server:settimeout(0)
				dataSocket = server:accept()
				if dataSocket ~= nil then
					server:close()
					server=nil
				end
			end
			if dataSocket ~=nil then 
				doExit = false
				dataSocket:setoption('tcp-nodelay',true)
				send = true
				sendGreeting = true;
				sendInit = false;
				initSent = false;
				dataCount = 0
				relayConnected = false
				if (relay == nil) then
					emu.message("Connected")
				end
			end
		else 
			if (relay ~= nil and relayConnected == false) then
				data, status = dataSocket:receive("*l")
				if data ~= nil then
					print(data)
					relay = data;
					relayConnected = true
					data = nil
					emu.message("Connected to relay")
				end
			else
				if dataCount == 0 then
					dataSocket:settimeout(0)
					data, status = dataSocket:receive(1)
					if data ~= nil then
						dataCount = data:sub(1,1):byte()
						if (dataCount == 0) then
							send = true
						end
						data = nil
					end
				end
				if dataCount > 0 then
					dataSocket:settimeout(0)
					data, status = dataSocket:receive(dataCount)
					if data ~= nil then
						send = true
						dataCount = 0	
					end
				end
				if status ~= "closed" then
					if flowControl == FLOW_CONTROL_OPTION.NONE then 
						messages = buildMessages()
						if string.len(messages) > 0 then
							dataSocket:settimeout(0)
							dataSocket:send(string.char(string.len(messages))..messages)
						end
					elseif send == true then
						messages = buildMessages()
						dataSocket:settimeout(0)
						dataSocket:send(string.char(string.len(messages))..messages)
						send = false
					end
				end
			end
			if status == "closed" then
				emu.message("Disconnected")
				doExit = relay ~= nil or isClient
				dataSocket:close()
				dataSocket = nil
			end
		end
		request = coroutine.yield(data)
		data = nil
	end
end

local _comm = coroutine.create(comm) 

local lastState = 0


while not doExit do 
    status, data = coroutine.resume(_comm,nil)
	if data ~= nil then
		consumeMessages(data)
	end
	if memory.readbyte(0x46) == 4 then
		if lossRequested == 1 then
			memory.writebyte(getWriteAddress(0x309),1)
			lossRequested = 0
		end
		if memory.readbyte(getWriteAddress(0x0317)) == 0 then
			if #keyFramesIn > 0 and keyFramesIn[1]:sub(1,1):byte() == 1 then
				keyFrame = table.remove(keyFramesIn,1)
				memory.writebyte(getWriteAddress(0x0305),keyFrame:sub(2,2):byte())
				memory.writebyte(getWriteAddress(0x0306),keyFrame:sub(3,3):byte())
				memory.writebyte(getWriteAddress(0x0325),keyFrame:sub(4,4):byte())
				memory.writebyte(getWriteAddress(0x0312),0xFE)
				memory.writebyte(getWriteAddress(0x0307),0x05)
				remoteCurrent = nil
			else 
				if remoteCurrent ~= nil then
					memory.writebyte(getWriteAddress(0x0305),remoteCurrent:sub(1,1):byte())
					memory.writebyte(getWriteAddress(0x0306),remoteCurrent:sub(2,2):byte())
					memory.writebyte(getWriteAddress(0x0325),remoteCurrent:sub(3,3):byte())
				end
				memory.writebyte(getWriteAddress(0x0312),0x00)
			end
		elseif gameMode == GAME_MODE.NORMAL then 
			
		end
	else
		remoteCurrent = nil
		keyFramesIn = {}
		lossRequested = false
	end
	emu.frameadvance()
end


emu.message("No Connection, Exiting Net Play")

