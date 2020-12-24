local socket =  require("socket.core")

local FLOW_CONTROL_OPTION = {NONE=0,["ONE-TO-ONE"]=1}
local GAME_MODE = {NORMAL=0}


local arg = "--relay 0 3.91.189.195"

--[[
	arg values
	
	to host: leave it empty
		arg = ""
	
	to be a direct client, make it the ip of the host
		arg = "127.0.0.1"
	
	to act as "host" for a relay connection, run the script before the client and enter the following.
		arg = "--relay host 3.91.189.195"

	to connect as a relay "cleint", get the "host" to tell you the connection number that appears in the console output when they run the script
		arg = "--relay <connection number> 3.91.189.195"
]]--


----------DIRECT-------------
--If using a direct P2P connection.
--HOST--
local host = "0.0.0.0"

--CLIENT--
--local host = "127.0.0.1"


----------RELAY--------------
--If connecting through the relay server. Both the host player and the client player should uncomment the following line.
--local host = "3.91.189.195"

--HOST--
--local relay = "host"

--CLIENT--
--local relay = "0" -- Zero is probably the correct value but this should be set the the value that the host player receives in their Console Output window.

-----------------------------

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
	elseif word == "--require-combo" then
		gameMode = GAME_MODE["REQUIRE-COMBOS"]
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

local isClient = (host ~= "0.0.0.0") and (relay ~= "host")

local port = 7777
local gameMode = GAME_MODE.NORMAL
local flowControl = 0
local relayConnected = false

local function getReadAddress(address)
	if isClient then 
		return address+0x500
	else
		return address
	end
end

local function getWriteAddress(address)
	if isClient then
		return address
	else
		return address+0x500
	end
end

local function getReadPlayerSetupAddress(address)
	if isClient then 
		return address+1
	else
		return address
	end
end

local function getWritePlayerSetupAddress(address)
	if isClient then 
		return address
	else
		return address+1
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
	if messageType == MESSAGE.SET_LEVEL then
		memory.writebyte(getWritePlayerSetupAddress(0x1E74), messages:sub(index+1,index+1):byte());
		memory.writebyte(getWriteAddress(0x340), messages:sub(index+1,index+1):byte());
		return index+2
	elseif messageType == MESSAGE.SET_SPEED then
		memory.writebyte(getWritePlayerSetupAddress(0x1E79), messages:sub(index+1,index+1):byte());
		memory.writebyte(getWriteAddress(0x37C), messages:sub(index+1,index+1):byte());
		return index+2
	elseif messageType == MESSAGE.SET_CURRENT_POS then
		remoteCurrent = messages:sub(index+1,index+3)
		return index+4
	elseif messageType == MESSAGE.SET_GAME_STATE then	
		remoteGameState = messages:sub(index+1,index+1):byte()
		return index+2
	elseif messageType == MESSAGE.REQUEST_START then
		startRequested = 1
		startSeed = {messages:sub(index+1,index+1):byte(), messages:sub(index+2,index+2):byte()}
		return index+3
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
	elseif messageType == MESSAGE.ADD_KEYFRAME then
		return insertKeyFrame(messages,index+1)
	elseif messageType == MESSAGE.REQUEST_CONTINUE then
		continueRequested = 1
		startSeed = {messages:sub(index+1,index+1):byte(), messages:sub(index+2,index+2):byte()}
		return index+3
	elseif messageType == MESSAGE.REQUEST_LOSS then
		lossRequested = 1
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
	current = string.char(memory.readbyte(getReadAddress(0x326)))..string.char(memory.readbyte(getReadAddress(0x327)))..string.char(memory.readbyte(getReadAddress(0x317)))
	if current ~= _current then
		dataOut = dataOut..string.char(MESSAGE.SET_CURRENT_POS)..current
		_current = current
	end
	level = memory.readbyte(getReadPlayerSetupAddress(0x1E74))
	if level ~= _level or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_LEVEL)..string.char(level)
		_level = level
	end
	speed = memory.readbyte(getReadPlayerSetupAddress(0x1E79))
	if speed ~= _speed or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_SPEED)..string.char(speed)
		_speed = speed
	end
	state = memory.readbyte(0x0BAF)
	if state ~= _state  or sendInit then
		dataOut = dataOut..string.char(MESSAGE.SET_GAME_STATE)..string.char(state)
		_state = state
	end
	if requestStart == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_START)..table.concat(startSeed)
		requestStart = 0
	end
	if (sendGreeting) then
		dataOut = dataOut..string.char(MESSAGE.GREETING)
		sendGreeting = false
	end
	if sendInit == true then
		dataOut = dataOut..string.char(MESSAGE.INIT)..string.char(flowControl)..string.char(gameMode)
		initSent = true
		sendInit = false
	end
	while #keyFramesOut > 0 do
		keyFrameOut = table.remove(keyFramesOut,1)
		dataOut = dataOut..string.char(MESSAGE.ADD_KEYFRAME)..keyFrameOut
	end
	if requestContinue == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_CONTINUE)..table.concat(startSeed)
		requestContinue = 0
	end
	if requestLoss == 1 then
		dataOut = dataOut..string.char(MESSAGE.REQUEST_LOSS)
		requestLoss = 0
	end
	return dataOut
end


local function handleInput() 
	local state = memory.readbyte(0x0BAF)
	if isClient then
		if state == 0x11 then
			if memory.readbyte(0x0c08) < 0x02 then
				p1Input = memory.getregister('x')
				leftRight = (p1Input % 0x0400) - (p1Input % 0x0100)
				memory.writeword(0x39,leftRight)
				memory.setregister('x',p1Input-leftRight)
			end
		elseif state == 7 and memory.readbyte(0xB0A) < 0x05 then
			p1Input = memory.getregister('x')
			memory.writeword(0x39,AND(p1Input,0xEFFF))
			memory.setregister('x',0)
		end
	elseif state == 7 and memory.readbyte(0xB0A) == 0x00 then
		p1Input = memory.getregister('x')
		p1Input = AND(p1Input,0xEFFF)
		memory.setregister('x',p1Input)
	end
end

local function handleInputPart2() 
	if isClient then
		memory.setregister('x',memory.readword(0x39))
	end
end

local function handleStart() 
	if not isClient and remoteGameState == 0x11 then
		if memory.readbyte(0xbaf) == 0x11 and AND(memory.readword(0x1dd9),0x1080) > 0 then
			requestStart = 1
			startSeed = {string.char(memory.readbyte(0x9e)),string.char(memory.readbyte(0x9f)) }
		end
	elseif startRequested == 1 and startSeed ~= nil then
		memory.writeword(0x1dd9,0x0080)	
		memory.writebyte(0x9e,startSeed[1])	
		memory.writebyte(0x9f,startSeed[2])
		startRequested = 0
	else
		memory.writeword(0x1dd9,AND(memory.readword(0x1dd9),0xEF7F))
	end
end

local function handleContinue() 
	if not isClient then
		if AND(memory.readword(0x0276),0x1080) > 0 then
			requestContinue = 1   
			startSeed = {string.char(memory.readbyte(0x9e)),string.char(memory.readbyte(0x9f)) }
		end
	else 
		if continueRequested == 1 then
			memory.writeword(0x0276,0x1000)
			memory.writebyte(0x9e,startSeed[1])	
			memory.writebyte(0x9f,startSeed[2])
			continueRequested = 0	
		end
	end
end



local function collectGarbage() 
	if (memory.getregister('x') == 0) == isClient then
		if memory.readbyte(getWriteAddress(0x32e)) == 2 then
			table.insert(keyFramesOut,string.char(2)..string.char(memory.getregister('y'))..string.char(memory.readbyte(getWriteAddress(0x334)))..string.char(memory.readbyte(getWriteAddress(0x335))))
		elseif	memory.readbyte(getWriteAddress(0x32e)) == 3 then
			table.insert(keyFramesOut,string.char(3)..string.char(memory.getregister('y'))..string.char(memory.readbyte(getWriteAddress(0x334)))..string.char(memory.readbyte(getWriteAddress(0x336)))..string.char(memory.readbyte(getWriteAddress(0x335))))
		else
			table.insert(keyFramesOut,string.char(4)..string.char(memory.getregister('y'))..string.char(memory.readbyte(getWriteAddress(0x334)))..string.char(memory.readbyte(getWriteAddress(0x335)))..string.char(memory.readbyte(getWriteAddress(0x336)))..string.char(memory.readbyte(getWriteAddress(0x337))))
		end
	end
end

local function waitForNext()
	if (memory.getregister('x') == 0) == isClient then
		if #keyFramesIn > 0 and keyFramesIn[1]:sub(1,1):byte() == 0 then
		else
			memory.setregister('a',0x0000)
		end
	end
end

local skipNextDrop = false

local function handleLocalNext()
	if (memory.getregister('x') == 0) ~= isClient then
		table.insert(keyFramesOut, string.char(0))
	else
		if #keyFramesIn > 0 and keyFramesIn[1]:sub(1,1):byte() == 0 then
			table.remove(keyFramesIn,1)
		end
	end
end

local function preventLocalGarbage()
	if (memory.getregister('x') == 0) ~= isClient then
		memory.setregister('a',0x0000)
	end
end

local function preventRngCycle()
	if memory.readbyte(0xBB0) ~= 0x16 and memory.readword((memory.getregister('s')+1)) == 0x86ef then 
		memory.setregister('a',memory.readword(0x9e))
	end
end


local function consumeNext()
	
end	

memory.registerexec(0x808DBA,preventRngCycle)
memory.registerexec(0x808C98,handleInput)
memory.registerexec(0x808C9D,handleInputPart2)
memory.registerexec(0x82C0EC,handleStart)
memory.registerexec(0x829243,handleContinue)
memory.registerexec(0x82919A,handleContinue)
memory.registerexec(0x829db7,collectGarbage)
memory.registerexec(0x829de5,collectGarbage)
memory.registerexec(0x828c9f,preventLocalGarbage)
memory.registerexec(0x828d46,handleLocalNext)

memory.registerexec(0x828caa,waitForNext)

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
	if memory.readbyte(0xBAF) == 0x07 then
		newState = memory.readbyte(getReadAddress(0x0305))
		if (newState == 6 and lastState == 5) or (newState == 0x0a and lastState ~= 0x0a) then
			table.insert(keyFramesOut, string.char(1)..string.char(memory.readbyte(getReadAddress(0x326)))..string.char(memory.readbyte(getReadAddress(0x327)))..string.char(memory.readbyte(getReadAddress(0x317))))
		end
		lastState = newState
	end
	status, data = coroutine.resume(_comm,nil)
	if data ~= nil then
		consumeMessages(data)
	end
	if memory.readbyte(0xBAF) == 0x07 and memory.readbyte(0xB0A) == 0 then
		if memory.readbyte(getWriteAddress(0x305)) == 5 then
			if #keyFramesIn > 0 then
				if (keyFramesIn[1]:sub(1,1):byte() == 1) then
					keyFrame = table.remove(keyFramesIn,1)
					memory.writebyte(getWriteAddress(0x0326),keyFrame:sub(2,2):byte())
					memory.writebyte(getWriteAddress(0x0327),keyFrame:sub(3,3):byte())
					memory.writebyte(getWriteAddress(0x0317),keyFrame:sub(4,4):byte())
					remoteCurrent = nil
				end
				memory.writebyte(getWriteAddress(0x0347),0x00)
			else 
				if remoteCurrent ~= nil then
					memory.writebyte(getWriteAddress(0x0326),remoteCurrent:sub(1,1):byte())
					memory.writebyte(getWriteAddress(0x0327),remoteCurrent:sub(2,2):byte())
					memory.writebyte(getWriteAddress(0x0317),remoteCurrent:sub(3,3):byte())
				end
				memory.writebyte(getWriteAddress(0x0347),0x02)
			end
		elseif memory.readbyte(getWriteAddress(0x305)) == 6 and #keyFramesIn > 0 and keyFramesIn[1]:sub(1,1):byte() > 1 then
			garbageIn = table.remove(keyFramesIn,1)
			garbageCount = garbageIn:sub(1,1):byte()
			levelDataPointer = getWriteAddress(0x111)
			firstGarbage = levelDataPointer+garbageIn:sub(2,2):byte()
			memory.writebyte(firstGarbage,garbageIn:sub(3,3):byte())
			if garbageCount == 2 then
				memory.writebyte(firstGarbage+4,garbageIn:sub(4,4):byte())
			else
				memory.writebyte(firstGarbage+2,garbageIn:sub(4,4):byte())
				memory.writebyte(firstGarbage+4,garbageIn:sub(5,5):byte())
				if garbageCount > 3 then
					memory.writebyte(firstGarbage+6,garbageIn:sub(6,6):byte())
				end
			end
			memory.writebyte(getWriteAddress(0x305),0x08)
		end
	else
		remoteCurrent = nil
		keyFramesIn = {}
		lossRequested = false
		skipNextDrop = false;
	end
	emu.frameadvance()
end

emu.message("No Connection, Exiting Net Play")