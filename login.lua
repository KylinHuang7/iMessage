-- 适用屏幕参数
SCREEN_RESOLUTION="640x960";
SCREEN_COLOR_BITS=32;

SCRIPT_VERSION=10005;
SSH="/usr/bin/ssh mobile@114.80.77.83 -p 12205 -i /var/mobile/.ssh/id_rsa ";
UPDATE="/usr/bin/scp -P 12205 mobile@114.80.77.83:./login.lua /var/touchelf/scripts/login.lua";

function isNetworkOK()
	time = getNetTime();
	if time == -1 then
		return false;
	else
		return true;
	end
end

function waitColor(x, y, color, timeout)
    local funcStart = os.time();
    local c = getColor(x, y);
    while c ~= color do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        mSleep(1000);
        c = getColor(x, y);
    end
    return true;
end

function waitChangeColor(x, y, color, timeout)
    local funcStart = os.time();
    local c = getColor(x, y);
    while c == color do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        mSleep(1000);
        c = getColor(x, y);
    end
    return true;
end

function waitColorPairs(x1, y1, color1, x2, y2, color2, timeout)
    local funcStart = os.time();
    local c1 = getColor(x1, y1);
    local c2 = getColor(x2, y2);
    while c1 ~= color1 and c2 ~= color2 do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        mSleep(1000);
        c1 = getColor(x1, y1);
        c2 = getColor(x2, y2);
    end
    return true;
end

function waitChangeColorPairs(x1, y1, color1, x2, y2, color2, timeout)
    local funcStart = os.time();
    local c1 = getColor(x1, y1);
    local c2 = getColor(x2, y2);
    while c1 == color1 and c2 == color2 do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        mSleep(1000);
        c1 = getColor(x1, y1);
        c2 = getColor(x2, y2);
    end
    return true;
end

function waitColorAppear(color, timeout)
    local funcStart = os.time();
    x, y = findColor(color);
    while x == -1 and y == -1 do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        mSleep(1000);
        x, y = findColor(color);
    end
    return x, y;
end

function scrollUntilColorAppear(color, timeout)
	local funcStart = os.time();
	x, y = findColor(color);
    local step = 25;
	while x == -1 and y == -1 do
        step = 0 - step;
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        local t = 500 - 16 * step;
        touchDown(0, 320, t);
        while t >= 100 and t <= 900 do
        	t = t + step;
        	mSleep(50);
        	touchMove(0, 320, t);
        end
        mSleep(50);
        touchUp(0);
        mSleep(1000);
        x, y = findColor(color);
	end
	return x, y;
end

function stepOpenSetting(timeout)
    local funcStart = os.time();
    os.execute("/usr/bin/killall -9 Preferences");
    mSleep(3000);
    os.execute("/usr/bin/open com.apple.Preferences");
    mSleep(2000);

    while waitColor(60, 195, 0xEF8522, 2) == false do  -- the plane's color in flight mode
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        touchDown(6, 30, 83);  -- back button
        touchUp(6);
        mSleep(2000);
    end

    return true;
end

function stepOpenWiFi(timeout)
    if not stepOpenSetting(timeout) then
        return false;
    end

    touchDown(1, 320, 280); -- WiFi
    touchUp(1);
    mSleep(5000);

    return true;
end

function stepOpenMessage(timeout)
    local funcStart = os.time();
    if not stepOpenSetting(timeout) then
        return false;
    end

    local x, y = scrollUntilColorAppear(0x00D300, timeout - os.difftime(os.time(), funcStart));
    touchDown(2, 320, y);
    touchUp(2);
    mSleep(2000);

    -- if loged
    if getColor(490, 200) == 0x3398EE then  -- iMessage toggle
        stepLogout(20);
        x, y = findColor(0x00D300);
        while x == -1 and y == -1 do
            if os.difftime(os.time(), funcStart) > timeout then
                return false;
            end
            x, y = findColor(0x00D300);
        end
        touchDown(2, 320, y);
        touchUp(2);
        mSleep(2000);
    end
    return true;
end

function stepInputAccount(account, passwd)
    touchDown(3, 320, 390); -- account
    touchUp(3);
    mSleep(1000);
    if getColor(580, 330) == 0xACACAC then  -- clear
        touchDown(4, 580, 330);
        touchUp(4);
        mSleep(2000);
    end
    inputText(account ..  "\n");
    mSleep(2000);
    inputText(passwd);
    mSleep(2000);
    inputText("\n");
    mSleep(2000);
end

function stepWaitNext(account, passwd, timeout)
    if timeout <= 0 then
        return false;
    end
    local funcStart = os.time();
    stepInputAccount(account, passwd);
    if waitChangeColor(580, 90, 0x7C92AE, timeout) == false then    -- next
        return false;
    end
    mSleep(3000);

    local color = getColor(580, 90);
    if color == 0x2260DD then   -- next
        return true;
    elseif color == 0x404C5A then
        color = getColor(336, 489);
        if color == 0xFFFFFF then
            -- network fail, wait
            touchDown(5, 320, 570);
            touchUp(5);
            mSleep(2000);
            return stepWaitNext(account, passwd, timeout - os.difftime(os.time(), funcStart));
        elseif color == 0x273861 then
            -- password wrong, relogin
            touchDown(5, 320, 570);
            touchUp(5);
            mSleep(2000);
            touchDown(6, 320, 605);
            touchUp(6);
            mSleep(2000);
            return stepWaitNext(account, passwd, timeout - os.difftime(os.time(), funcStart));
        elseif color == 0xF6F6F6 then
            -- input pass
            return false;
        end
        return false;
    end
end

function stepNext(timeout)
    if timeout <= 0 then
        return false;
    end
    local funcStart = os.time();
    touchDown(7, 580, 90);  -- next
    touchUp(7);
    mSleep(1000);
    if waitChangeColor(580, 90, 0x2260DD, timeout) == false then
        return false;
    end
    mSleep(3000);
    if waitChangeColorPairs(580, 90, 0x7C92AE, 490, 200, 0xC5CCD4, timeout - os.difftime(os.time(), funcStart)) == false then
        return false;
    end
    mSleep(3000);
    if getColor(580, 90) == 0x2260DD then
        -- select zone
        touchDown(6, 320, 370);
        touchUp(6);
        mSleep(1000);
        touchDown(5, 320, 370);
        touchUp(5);
        mSleep(1000);
        return stepNext(timeout - os.difftime(os.time(), funcStart));
    elseif getColor(580, 90) == 0x123272 then
        -- mail error
        touchDown(6, 320, 560);
        touchUp(6);
        mSleep(1000);
        return stepNext(timeout - os.difftime(os.time(), funcStart));
    elseif getColor(490, 200) == 0x3398EE then
        -- success
        return true;
    elseif getColor(490, 200) == 0x1E5A8D then
        -- active error
        touchDown(6, 320, 560);
        touchUp(6);
        mSleep(1000);
        return true;
    end
    return false
end

function stepLogout(timeout)
    local funcStart = os.time();

    touchDown(8, 320, 630); -- account
    touchUp(8);
    mSleep(1000);
    if not waitChangeColor(490, 200, 0x3398EE, timeout) then  -- iMessage toggle
        return false;
    end 
    touchDown(9, 320, 190); -- apple id
    touchUp(9);
    mSleep(1000);
    if not waitColor(320, 60, 0x555D67, timeout - os.difftime(os.time(), funcStart)) then    -- log out button
        return false;
    end
    touchDown(5, 320, 600); -- log out button
    touchUp(5);
    mSleep(2000);
    return true;
end

function forgetWiFi(timeout)
	local funcStart = os.time();
    if not stepOpenWiFi(timeout) then
        return false;
    end

    x, y = scrollUntilColorAppear(0x324F85, timeout - os.difftime(os.time(), funcStart)); -- the WiFi joined

    touchDown(2, 578, y);
    touchUp(2);
    mSleep(2000);

    touchDown(3, 320, 200); -- ignore
    touchUp(3);
    mSleep(1000);

    touchDown(4, 320, 740); -- ignore in sheet
    touchUp(4);
    mSleep(1000);

    return true;
end

function getIP()
    cmd = io.popen('/usr/sbin/ipconfig getifaddr en0');
    if not cmd then
        return nil;
    end
    line = cmd:read("*l");
    cmd:close();
    if not line then
        return nil;
    end
    return line;
end

function getMAC()
    cmd = io.popen('/usr/sbin/nvram wifiaddr');
    if not cmd then
        return nil;
    end
    line = cmd:read("*l");
    cmd:close();
    if not line then
        return nil;
    end
    sep_index = string.find(line, "\t");
    if not sep_index then
        return nil;
    end
    return string.sub(line, sep_index + 1);
end

function generateIPByMAC()
    macaddr = getMAC();
    device_id = tonumber(string.sub(macaddr, 4, 5));
    math.randomseed(os.time());
    ipd = math.random(1, 253);
    return "10.0." .. tostring(100+device_id) .. '.' .. tostring(ipd);
end

function changeMAC()
    macaddr = getMAC();
    device_times = tonumber(string.sub(macaddr, 1, 1), 16);
    next_times = device_times + 1;
    if next_times >= 16 then
        next_times = 0;
    end
    mac_start = string.format("%X", next_times) .. string.sub(macaddr, 2, 6);
    math.randomseed(os.time());
    mac_last = string.format("%X%X:%X%X:%X%X:%X%X", math.random(0, 15), math.random(0, 15), math.random(0, 15), math.random(0, 15), math.random(0, 15), math.random(0, 15), math.random(0, 15), math.random(0, 15));
    newmac = mac_start .. mac_last;
    os.execute('/usr/bin/sudo /usr/sbin/nvram -d wifiaddr');
    os.execute('/usr/bin/sudo /usr/sbin/nvram wifiaddr=' .. newmac);
    os.execute('/usr/bin/sudo /sbin/reboot');    
end

function joinWiFi(timeout)
	local funcStart = os.time();
    if not stepOpenWiFi(timeout) then
        return false;
    end

    touchDown(3, 320, 372); -- the first network
    touchUp(3);
    mSleep(2000);

    x, y = waitColorAppear(0x324F85, timeout - os.difftime(os.time(), funcStart)); -- the WiFi joined

    touchDown(1, 578, y);
    touchUp(1);
    mSleep(2000);

    touchDown(4, 520, 380); -- static
    touchUp(4);
    mSleep(1000);

    touchDown(5, 320, 510); -- IP
    touchUp(5);
    mSleep(1000);

    local ip = generateIPByMAC();
    local mask = '255.255.0.0';
    local gateway = "10.0.0.5";
    local dns = "8.8.8.8";

    inputText("\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f");
    mSleep(2000);
    inputText(ip .. "\n");
    mSleep(2000);
    inputText("\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f");
    mSleep(2000);
    inputText(mask .. "\n");
    mSleep(2000);
    inputText("\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f");
    mSleep(2000);
    inputText(gateway .. "\n");
    mSleep(2000);
    inputText("\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f\x7f");
    mSleep(2000);
    inputText(dns .. "\n");
    mSleep(2000);

    touchDown(6, 30, 83);   -- back button
    touchUp(6);
    mSleep(5000);

    local result = waitColor(88, 30, 0x4E86E7, timeout - os.difftime(os.time(), funcStart));  -- wifi icon
    if result then
        return isNetworkOK();
    else
        return result;
    end
end

function doLogin(account, passwd, timeout)
    local funcStart = os.time();
    if not stepOpenMessage(timeout) then
        return false;
    end
    if not stepWaitNext(account, passwd, timeout - os.difftime(os.time(), funcStart)) then
        return false;
    end
    if not stepNext(timeout - os.difftime(os.time(), funcStart)) then
        return false;
    end
    return true;
end

function doLogout(timeout)
    if not stepOpenMessage(timeout) then
        return false;
    end
    return true;
end

function loadSetting(id)
    cmd = io.popen(SSH .. ' ./device_cmd.sh setting ' .. id .. ' ' .. SCRIPT_VERSION, 'r');
    if not cmd then
        return nil;
    end
    output = cmd:read('*l');
    cmd:close();
    if not output then
        return nil;
    end
    value = {};
    for v in string.gmatch(output, "%S+") do
        table.insert(value, v);
    end
    if tonumber(value[1]) ~= SCRIPT_VERSION then
        os.execute(UPDATE);
    end
    return {network_timeout = tonumber(value[2]); login_timeout = tonumber(value[3]); sync_timeout = tonumber(value[4])};
end

function commitNetworkSuccess(id)
    ipaddress = getIP();
    mac = getMAC();
    os.execute(SSH .. ' ./device_cmd.sh network ' .. id .. ' ' .. mac .. ' ' .. ipaddress);
    return true;
end

function getAccount(id)
    cmd = io.popen(SSH .. ' ./device_cmd.sh account ' .. id, 'r');
    if not cmd then
        return nil;
    end
    output = cmd:read('*l');
    cmd:close();
    if not output then
        return nil;
    end
    value = {};
    for v in string.gmatch(output, "%S+") do
        table.insert(value, v);
    end
    return value[1], value[2]    
end

function commitLoginSuccess(id)
    os.execute(SSH .. ' ./device_cmd.sh login ' .. id .. ' 1');
    return true;
end

function commitLoginFail(id)
    os.execute(SSH .. ' ./device_cmd.sh login ' .. id .. ' 2');
    return true;
end

function waitVMStatus(id, timeout)
    local funcStart = os.time();
    while true do
        if os.difftime(os.time(), funcStart) > timeout then
            return false;
        end
        cmd = io.popen(SSH .. ' ./device_cmd.sh sender ' .. id, 'r');
        if cmd then
            output = cmd:read('*n');
            cmd:close();
            if output == 1 then
                return true;
            elseif output == 2 then
                return false;
            end
        end
        mSleep(5000);
    end
end

function commitLogoutSuccess(id)
    os.execute(SSH .. ' ./device_cmd.sh logout ' .. id);
    return true;
end

function doMain(id, settings)
	if isNetworkOK() then
		server_settings = loadSetting(id);
		if server_settings ~= nil then
			settings = server_settings;
		end
		forgetWiFi(20);
	end
	if not joinWiFi(settings["network_timeout"]) then
        return false;
    end
    commitNetworkSuccess(id);

    local times = 0
    while true do
        times = times + 1;
        account, passwd = getAccount(id);
        if doLogin(account, passwd, settings["login_timeout"]) then
            commitLoginSuccess(id);
            if waitVMStatus(id, settings["sync_timeout"]) then
                doLogout(20);
                commitLogoutSuccess(id);
                forgetWiFi(20);
                changeMAC();
                return true;
            else
                doLogout(20);
                commitLogoutSuccess(id);
            end
        else
            commitLoginFail(id);
        end
        mSleep(5000);
        if times >= 3 then
            return false;
        end
    end
end

-- 主入口
function main()
	rotateScreen(0);

    file = io.open("/var/touchelf/id", "r");
    if not file then
        return false;
    end
    id = file:read("*n");
    file:close();
    if not id then
        return false;
    end

    settings = {network_timeout = 300; login_timeout = 180; sync_timeout = 1800};

    while true do
        doMain(id, settings);
mSleep(5000);
    end
end    
