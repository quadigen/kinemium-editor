return function(signal)
	local active = {}
	local snapshot = {}
	local connection
	local stepping = false
	local serial = 0

	local function disconnectIfIdle()
		if not stepping and next(active) == nil and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function step(dt)
		if stepping then return end
		stepping = true
		for task, version in pairs(active) do
			snapshot[task] = version
		end
		for task, version in pairs(snapshot) do
			if active[task] == version then
				local ok, moving = pcall(task.step, dt)
				if not ok then
					warn("Editor animation failed:", moving)
				end
				if active[task] == version and (not ok or moving ~= true) then
					active[task] = nil
				end
			end
			snapshot[task] = nil
		end
		stepping = false
		disconnectIfIdle()
	end

	local scheduler = {}
	function scheduler.newTask(callback)
		local task = { step = callback }
		local destroyed = false
		function task:Wake()
			if destroyed then return end
			serial = serial + 1
			active[self] = serial
			if not connection then
				connection = signal:Connect(step)
			end
		end
		function task:Stop()
			active[self] = nil
			disconnectIfIdle()
		end
		function task:Destroy()
			destroyed = true
			self:Stop()
		end
		return task
	end

	return scheduler
end
