https       = require 'https'
Slack = require './'
MemJS = require 'memjs'

memjs = MemJS.Client.create()

token = process.env.KUDOBOT_TOKEN # Add a bot at https://my.slack.com/services/new/bot and copy the token here.
autoReconnect = true
autoMark = true

potluck_id = process.env.POTLUCK_ID
jamila_id = process.env.JAMILA_ID

jamila_dm = null
potluck_dm = null
team_channel = null

awards =
  credit: "Do the Extra Credit"
  vibes: "Bring Good Vibes"
  student: "Always a Student"
  group: "Clever is a Group Project"
  classroom: "Leave the Classroom Better than you Found it"
  textbook: "Don't Trust the Textbook"
  security: "Data Defender + Security"
  cleaver: "Cleaver Prize"

shortnames =  [
  "credit",
  "vibes",
  "student",
  "group",
  "classroom",
  "textbook",
  "security",
  "cleaver" 
]

# YES, I KNOW THAT THESE DICTIONARIES ARE NAMED BACKWARDS
# id => username
user_ids = {}
# username => id
usernames = {}

# people who can set the current kudos holder
godUsers = ["@jam", "@p"]

slack = new Slack(token, autoReconnect, autoMark)

slack.on 'open', ->
  channels = []
  groups = []
  users = slack.users
  unreads = slack.getUnreadCount()

  memjs.set "credit", jamila_id
  memjs.set "vibes", jamila_id
  memjs.set "student", jamila_id
  memjs.set "group", jamila_id
  memjs.set "classroom", jamila_id
  memjs.set "textbook", jamila_id
  memjs.set "security", jamila_id
  memjs.set "cleaver", jamila_id

  # Get all the channels that bot is a member of
  channels = ("##{channel.name}" for id, channel of slack.channels when channel.is_member)
  team_channel = slack.getChannelByName("#team")

  # Get all groups that are open and not archived 
  groups = (group.name for id, group of slack.groups when group.is_open and not group.is_archived)

  #console.log "Yo! Welcome to Slack. You are @#{slack.self.name} of #{slack.team.name}"
  #console.log 'You are in: ' + channels.join(', ')

  # get the DM id to message jamila and potluck
  slack.openDM jamila_id, (value) ->
    jamila_dm_id = value.channel.id
    jamila_dm = slack.getDMByID(jamila_dm_id)
  slack.openDM potluck_id, (value) ->
    potluck_dm_id = value.channel.id
    potluck_dm = slack.getDMByID(potluck_dm_id)

  # set the reverse dicts
  for user of users
    user_ids[user] = users[user]['name']
    usernames[users[user]['name']] = user
  

slack.on 'message', (message) ->
  channel = slack.getChannelGroupOrDMByID(message.channel)

  user = slack.getUserByID(message.user)
  response = ''

  {type, ts, text} = message

  channelName = if channel?.is_channel then '#' else ''
  channelName = channelName + if channel then channel.name else 'UNKNOWN_CHANNEL'

  userName = if user?.name? then "@#{user.name}" else "UNKNOWN_USER"

  console.log """
    Just Received: #{type} #{channelName} #{userName} #{ts} "#{text}"
  """

  if type is 'message' and text? and not channel.is_channel and userName isnt '@kudobot'
    words = text.split(' ')
    if words[0] is "set" and words.length > 2 and userName in godUsers
      holder = words[1]
      award = words[2]

      if holder[1] is "@"
        # to get the raw user ID
        holder = holder.slice(2, holder.length - 1)
      if (user_ids[holder]?) and (awards[award]?)
        set_holder holder, award, channel

      else
        bad_set channel
    else if words[0] is "set"
      bad_set channel
    else if text.indexOf("nominate") is 0
      award = words[2]
      if not awards[award]?
        bad_nomination channel
      else
        jam_pot_notif words, userName
        holder_notif words, userName
        team_notif award
        good_nomination channel

    else
      bad_nomination channel
 
  else
    typeError = if type isnt 'message' then "unexpected type #{type}." else null
    textError = if not text? then 'text was undefined.' else null
    channelError = if not channel? then 'channel was undefined.' else null

    errors = [typeError, textError, channelError].filter((element) -> element isnt null).join ' '

    console.log """
      @#{slack.self.name} could not respond. #{errors}
    """


slack.on 'error', (error) -> console.error "Error: #{error}"


slack.login()


set_holder = (holder, award, channel) ->
  response = "OK, set "+user_ids[holder]+" as current holder of "+awards[award]+"\n"

  memjs.set award, holder

  response += "current holders are: \n"
  for awrd in shortnames
    response += "" + awrd + ": @"
    memjs.get awrd, (err, holder) ->
      if holder
        response += holder + "\n"
      else
        response += "error? let Potluck know you got this message\n"
    
  channel.send response

bad_set = (channel) ->
  response = "Usage: `set [award holder] [award]`\n"
  response += "'award holder' should be the slack username, prepended by @\n"
  response += "`award` should be one of: `credit`, `vibes`, `student`, `group`, `classroom`, `textbook`, `cleaver` or `security`"
  channel.send response

team_notif = (award) ->
  team_msg = "Someone just made a nomination for "+awards[award]+"!\n"
  team_msg += "You can make a nomination by DMing kudobot: `nominate [nominee] [award] [reason]`"
  team_channel.send team_msg

holder_notif = (words, userName) ->
  award = words[2]
  holder_msg = "Hey! "+ userName+" made a nomination!\n"
  holder_msg += words[1] + " has been nominated for " + award
  holder_msg += " for " + words.slice(3).join(' ') + "\n"

  memjs.get award, (err, holder) ->
  if holder
    holder_id = holder
  else 
    # this is a problem
    return

  slack.openDM holder_id, (value) ->
    holder_dm_id = value.channel.id
    holder_dm = slack.getDMByID(holder_dm_id)
    holder_dm.send holder_msg

jam_pot_notif = (words, userName) ->
  award = words[2]
  jamila_msg = "Hey Jamila/Potluck, "+ userName+" made a nomination!\n"
  jamila_msg += words[1] + " has been nominated for " + award
  jamila_msg += " for " + words.slice(3).join(' ') + "\n"
  jamila_dm.send jamila_msg
  potluck_dm.send jamila_msg

good_nomination = (channel) ->
  response = "Great! Your nomination has been received"
  channel.send response

bad_nomination = (channel) ->
  response = "Usage: `nominate [nominee] [award] [reason]`\n"
  response += "`nominee` should be a single word name\n"
  response += "`award` should be one of: `credit`, `vibes`, `student`, `group`, `classroom`, `textbook`, `cleaver` or `security`"
  response += "\nCurrent Award holders are: \n"
  for awrd in shortnames
    response += "_" + awards[awrd] + "_: *@"
    memjs.get awrd, (err, holder) ->
      if holder
        response += user_ids[holder] + "*\n"
      else
        response += "error? let Potluck know you got this message*\n"
    

  channel.send response

