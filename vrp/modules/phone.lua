
local lang = vRP.lang
local htmlEntities = module("lib/htmlEntities")

-- basic phone module

local Phone = class("Phone", vRP.Extension)

-- SUBCLASS

Phone.User = class("User")

-- send an sms from an user to a phone number
-- return true on success
function Phone.User:sendSMS(phone, msg)
  local cfg = vRP.EXT.Phone.cfg

  if string.len(msg) > 0 then
    if string.len(msg) > cfg.sms_size then -- clamp sms
      sms = string.sub(msg,1,cfg.sms_size)
    end

    local cid, uid = vRP.EXT.Identity:getByPhone(phone)
    if cid then
      local tuser = vRP.users[uid]
      if tuser and tuser.cid == cid then
        local from = tuser:getPhoneDirectoryName(self.identity.phone).." ("..self.identity.phone..")"

        vRP.EXT.Base.remote._notify(tuser.source,lang.phone.sms.notify({from, msg}))
        vRP.EXT.GUI.remote._playAudioSource(tuser.source, cfg.sms_sound, 0.5)
        tuser:addSMS(self.identity.phone, msg)
        return true
      end
    end
  end
end

function Phone.User:addSMS(phone, msg)
  if #self.phone_sms >= vRP.EXT.Phone.cfg.sms_history then -- remove last sms of the table
    table.remove(self.phone_sms)
  end

  table.insert(self.phone_sms,1,{phone,msg}) -- insert new sms at first position {phone,message}
end

-- get directory name by number for a specific user
function Phone.User:getPhoneDirectoryName(phone)
  return self.cdata.phone_directory[phone] or "unknown"
end

-- call from a user to a phone number
-- return true if the communication is established
function Phone.User:phoneCall(phone)
  local cfg = vRP.EXT.Phone.cfg

  local cid, uid = vRP.EXT.Identity:getByPhone(phone)
  if cid then
    local tuser = vRP.users[uid]
    if tuser and tuser.cid == cid then
      local to = self:getPhoneDirectoryName(phone).." ("..phone..")"
      local from = tuser:getPhoneDirectoryName(self.identity.phone).." ("..self.identity.phone..")"

      vRP.EXT.Phone.remote._hangUp(self.source) -- hangup phone of the caller
      vRP.EXT.Phone.remote._setCallWaiting(self.source, tuser.source, true) -- make caller to wait the answer

      -- notify
      vRP.EXT.Base.remote._notify(self.source,lang.phone.call.notify_to({to}))
      vRP.EXT.Base.remote._notify(tuser.source,lang.phone.call.notify_from({from}))

      -- play dialing sound
      vRP.EXT.GUI.remote._setAudioSource(self.source, "vRP:phone:dialing", cfg.dialing_sound, 0.5)
      vRP.EXT.GUI.remote._setAudioSource(tuser.source, "vRP:phone:dialing", cfg.ringing_sound, 0.5)

      local ok = false

      -- send request to called
      if tuser:request(lang.phone.call.ask({from}), 15) then -- accepted
        vRP.EXT.Phone.remote._hangUp(tuser.source) -- hangup phone of the receiver
        vRP.EXT.GUI.remote._connectVoice(tuser.source, "phone", self.source) -- connect voice
        ok = true
      else -- refused
        vRP.EXT.Base.remote._notify(self.source,lang.phone.call.notify_refused({to})) 
        vRP.EXT.Phone.remote._setCallWaiting(self.source, tuser.source, false) 
      end

      -- remove dialing sound
      vRP.EXT.GUI.remote._removeAudioSource(self.source, "vRP:phone:dialing")
      vRP.EXT.GUI.remote._removeAudioSource(tuser.source, "vRP:phone:dialing")

      return ok
    end
  end
end

-- send an smspos from an user to a phone number
-- return true on success
function Phone.User:sendSMSPos(phone, x,y,z)
  local cfg = vRP.EXT.Phone.cfg

  local cid, uid = vRP.EXT.Identity:getByPhone(phone)
  if cid then
    local tuser = vRP.users[uid]
    if tuser and tuser.cid == cid then
      local from = tuser:getPhoneDirectoryName(self.identity.phone).." ("..self.identity.phone..")"
      vRP.EXT.GUI.remote._playAudioSource(tuser.source, cfg.sms_sound, 0.5)
      vRP.EXT.Base.remote._notify(tuser.source,lang.phone.smspos.notify({from})) -- notify
      -- add position for 5 minutes
      local bid = vRP.EXT.Map.remote.addBlip(tuser.source,x,y,z,162,37,from)
      SetTimeout(cfg.smspos_duration*1000,function()
        vRP.EXT.Map.remote._removeBlip(tuser.source,{bid})
      end)

      return true
    end
  end
end

-- PRIVATE METHODS

-- menu: phone directory entry
local function menu_phone_directory_entry(self)
  local function m_remove(menu) -- remove directory entry
    local user = menu.user
    user.cdata.phone_directory[menu.data.phone] = nil
    user:closeMenu(menu) -- close entry menu (removed)
  end

  local function m_sendsms(menu) -- send sms to directory entry
    local user = menu.user
    local phone = menu.data.phone

    local msg = user:prompt(lang.phone.directory.sendsms.prompt({self.cfg.sms_size}),"")
    msg = sanitizeString(msg,self.sanitizes.text[1],self.sanitizes.text[2])
    if user:sendSMS(phone, msg) then
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.sent({phone}))
    else
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.not_sent({phone}))
    end
  end

  local function m_sendpos(menu) -- send current position to directory entry
    local user = menu.user
    local phone = menu.data.phone

    local x,y,z = vRP.EXT.Base.remote.getPosition(user.source)
    if user:sendSMSPos(phone, x,y,z) then
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.sent({phone}))
    else
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.not_sent({phone}))
    end
  end

  local function m_call(menu) -- call player
    local user = menu.user
    local phone = menu.data.phone

    if not user:phoneCall(phone) then
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.call.not_reached({phone}))
    end
  end

  vRP.EXT.GUI:registerMenuBuilder("phone.directory.entry", function(menu)
    menu.title = htmlEntities.encode(menu.user:getPhoneDirectoryName(menu.data.phone))
    menu.css.header_color = "rgba(0,125,255,0.75)"

    menu:addOption(lang.phone.directory.call.title(), m_call)
    menu:addOption(lang.phone.directory.sendsms.title(), m_sendsms)
    menu:addOption(lang.phone.directory.sendpos.title(), m_sendpos)
    menu:addOption(lang.phone.directory.remove.title(), m_remove)
  end)
end

-- menu: phone directory
local function menu_phone_directory(self)
  local function m_add(menu) -- add to directory
    local user = menu.user

    local phone = user:prompt(lang.phone.directory.add.prompt_number(),"")
    local name = user:prompt(lang.phone.directory.add.prompt_name(),"")
    name = sanitizeString(tostring(name),self.sanitizes.text[1],self.sanitizes.text[2])
    phone = sanitizeString(tostring(phone),self.sanitizes.text[1],self.sanitizes.text[2])
    if string.len(name) > 0 and string.len(phone) > 0 and string.len(name) <= 75 and string.len(phone) <= 75 then
      user.cdata.phone_directory[phone] = name -- set entry
      vRP.EXT.Base.remote._notify(user.source, lang.phone.directory.add.added())
      user:actualizeMenu()
    else
      vRP.EXT.Base.remote._notify(user.source, lang.common.invalid_value())
    end
  end

  local function m_entry(menu, value) 
    menu.user:openMenu("phone.directory.entry", {phone = value})
  end

  vRP.EXT.GUI:registerMenuBuilder("phone.directory", function(menu)
    menu.title = lang.phone.directory.title()
    menu.css.header_color="rgba(0,125,255,0.75)"

    menu:addOption(lang.phone.directory.add.title(), m_add)

    for phone, name in pairs(menu.user.cdata.phone_directory) do -- add directory entries
      menu:addOption(htmlEntities.encode(name), m_entry, htmlEntities.encode(phone), phone)
    end
  end)
end

-- menu: phone sms
local function menu_phone_sms(self)
  local function m_respond(menu, value)
    local user = menu.user
    local phone = value

    -- answer to sms
    local msg = user:prompt(lang.phone.directory.sendsms.prompt({self.cfg.sms_size}),"")
    msg = sanitizeString(msg,self.sanitizes.text[1],self.sanitizes.text[2])
    if user:sendSMS(phone, msg) then
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.sent({phone}))
    else
      vRP.EXT.Base.remote._notify(user.source,lang.phone.directory.sendsms.not_sent({phone}))
    end
  end

  vRP.EXT.GUI:registerMenuBuilder("phone.sms", function(menu)
    menu.title = lang.phone.sms.title()
    menu.css.header_color = "rgba(0,125,255,0.75)"

    -- add all SMS
    for i,sms in pairs(menu.user.phone_sms) do
      local from = menu.user:getPhoneDirectoryName(sms[1]).." ("..sms[1]..")"

      menu:addOption("#"..i.." "..from, m_respond,
        lang.phone.sms.info({from,htmlEntities.encode(sms[2])}), sms[1])
    end
  end)
end

-- menu: phone service
local function menu_phone_service(self)
  local function m_service(menu, value) -- alert a service
    local user = menu.user
    local service_name = value
    local service = self.cfg.services[service_name]

    local x,y,z = vRP.EXT.Base.remote.getPosition(user.source)
    local msg = user:prompt(lang.phone.service.prompt(),"")
    msg = sanitizeString(msg,self.sanitizes.text[1],self.sanitizes.text[2])
    vRP.EXT.Base.remote._notify(user.source,service.notify) -- notify player
    self:sendServiceAlert(user,service_name,x,y,z,msg) -- send service alert (call request)
  end

  vRP.EXT.GUI:registerMenuBuilder("phone.service", function(menu)
    menu.title = lang.phone.service.title()
    menu.css.header_color="rgba(0,125,255,0.75)"

    for k,service in pairs(self.cfg.services) do
      menu:addOption(k, m_service, nil, k)
    end
  end)
end

-- menu: phone announce
local function menu_phone_announce(self)
  -- build announce menu

  local function m_announce(menu, value) -- alert a announce
    local user = menu.user
    local announce = value

    if not announce.permission or user:hasPermission(announce.permission) then
      local msg = user:prompt(lang.phone.announce.prompt(),"")
      msg = sanitizeString(msg,self.sanitizes.text[1],self.sanitizes.text[2])
      if string.len(msg) > 10 and string.len(msg) < 1000 then
        if announce.price <= 0 or user:tryPayment(announce.price) then -- try to pay the announce
          vRP.EXT.Base.remote._notify(user.source, lang.money.paid({announce.price}))

          msg = htmlEntities.encode(msg)
          msg = string.gsub(msg, "\n", "<br />") -- allow returns

          -- send announce to all
          vRP.EXT.GUI.remote._announce(-1,announce.image,msg)
        else
          vRP.EXT.Base.remote._notify(user.source, lang.money.not_enough())
        end
      else
        vRP.EXT.Base.remote._notify(user.source, lang.common.invalid_value())
      end
    else
      vRP.EXT.Base.remote._notify(user.source, lang.common.not_allowed())
    end
  end

  vRP.EXT.GUI:registerMenuBuilder("phone.announce", function(menu)
    menu.title = lang.phone.announce.title()
    menu.css.header_color="rgba(0,125,255,0.75)"

    for k,announce in pairs(self.cfg.announces) do
      menu:addOption(k, m_announce, lang.phone.announce.item_desc({announce.price,announce.description or ""}), announce)
    end
  end)
end

-- menu: phone
local function menu_phone(self)
  local function m_directory(menu)
    menu.user:openMenu("phone.directory")
  end

  local function m_sms(menu)
    menu.user:openMenu("phone.sms")
  end

  local function m_service(menu)
    menu.user:openMenu("phone.service")
  end

  local function m_announce(menu)
    menu.user:openMenu("phone.announce")
  end

  local function m_hangup(menu)
    self.remote._hangUp(menu.user.source)
  end

  vRP.EXT.GUI:registerMenuBuilder("phone", function(menu)
    menu.title = lang.phone.title()
    menu.css.header_color = "rgba(0,125,255,0.75)"

    menu:addOption(lang.phone.directory.title(), m_directory,lang.phone.directory.description())
    menu:addOption(lang.phone.sms.title(), m_sms,lang.phone.sms.description())
    menu:addOption(lang.phone.service.title(), m_service,lang.phone.service.description())
    menu:addOption(lang.phone.announce.title(), m_announce,lang.phone.announce.description())
    menu:addOption(lang.phone.hangup.title(), m_hangup,lang.phone.hangup.description())
  end)
end

-- METHODS

function Phone:__construct()
  vRP.Extension.__construct(self)

  self.cfg = module("cfg/phone")
  self.sanitizes = module("cfg/sanitizes")

  -- menu builders

  menu_phone_directory_entry(self)
  menu_phone_directory(self)
  menu_phone_announce(self)
  menu_phone_service(self)
  menu_phone_sms(self)
  menu_phone(self)

  -- phone in main menu

  local function m_phone(menu)
    menu.user:openMenu("phone")
  end

  vRP.EXT.GUI:registerMenuBuilder("main", function(menu)
    if menu.user:hasPermission("player.phone") then
      menu:addOption(lang.phone.title(), m_phone)
    end
  end)
end


-- Send a service alert to all service listeners
--- sender: user or nil (optional, if not nil, it is a call request alert)
--- service_name: service name
--- x,y,z: coordinates
--- msg: alert message
function Phone:sendServiceAlert(sender, service_name,x,y,z,msg)
  local service = self.cfg.services[service_name]
  local answered = false
  if service then
    local targets = {}
    for _,user in pairs(vRP.users) do
      if user:hasPermission(service.alert_permission) then
        table.insert(targets, user)
      end
    end

    -- send notify and alert to all targets
    for _,user in pairs(targets) do
      vRP.EXT.Base.remote._notify(user.source,service.alert_notify..msg)
      -- add position for service.time seconds
      local bid = vRP.EXT.Map.remote.addBlip(user.source,x,y,z,service.blipid,service.blipcolor,"("..service_name..") "..msg)
      SetTimeout(service.alert_time*1000,function()
        vRP.EXT.Map.remote._removeBlip(user.source,bid)
      end)

      -- call request
      if sender then
        async(function()
          local ok = user:request(lang.phone.service.ask_call({service_name, htmlEntities.encode(msg)}), 30)
          if ok then -- take the call
            if not answered then
              -- answer the call
              vRP.EXT.Base.remote._notify(sender.source,service.answer_notify)
              vRP.EXT.Map.remote._setGPS(user.source,x,y)
              answered = true
            else
              vRP.EXT.Base.remote._notify(user.source,lang.phone.service.taken())
            end
          end
        end)
      end
    end
  end
end

-- EVENT
Phone.event = {}

function Phone.event:characterLoad(user)
  if not user.phone_sms then
    user.phone_sms = {}
  end

  if not user.cdata.phone_directory then
    user.cdata.phone_directory = {}
  end
end

function Phone.event:playerDeath(user)
  if self.cfg.clear_phone_on_death then
    user.phone_sms = {}
    user.cdata.phone_directory = {}
  end
end

vRP:registerExtension(Phone)