https       = require 'https'
Slack = require './'
ddb = require('dynamodb').ddb
  accessKeyId: process.env.AWS_ACCESS_KEY_ID_KUDOBOTDDB,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY_KUDOBOTDB,
  endpoint: 'dynamodb.us-west-1.amazonaws.com'

token = process.env.KUDOBOT_TOKEN # Add a bot at https://my.slack.com/services/new/bot and copy the token here.
autoReconnect = true
autoMark = true

table_name = 'kudobot'

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
godUsers = ["@jam", "@potluck"]

slack = new Slack(token, autoReconnect, autoMark)

slack.on 'open', ->
  users = slack.users

  team_channel = slack.getChannelByName("#team")

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
      if award[0] is '[' and award[award.length-1] is ']'
        award = award.substring(1, award.length-1)
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

# For Jamila/Potluck to set who is the current holder of the award
set_holder = (holder, award, channel) ->
  response = "OK, set "+user_ids[holder]+" as current holder of "+awards[award]+"\n"

  ddb.putItem table_name, {award: award, holder_id: holder}, {}, (err, res, cap) ->
    if err
      console.log err
      channel.send "Had an issue setting this holder - try again"
      return
    holders = []
    ddb.scan table_name, {}, (err, res) ->
      if err
        console.log err
        channel.send "Set holder. Hit an issue grabbing current holders - send kudobot another message to confirm it was set"
        return
      response += "current holders are: \n"
      for item in res.items
        response += "#{awards[item.award]}: @#{user_ids[item.holder_id]}\n"
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

  ddb.getItem table_name, award, null, {}, (err, res, cap) ->
    if err
      console.log err
      # TODO: send the person a response that there was an error notifying the holder
      return
    holder_id = res.holder_id
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

  console.log "Scanning Dynamodb table #{table_name}."
  ddb.scan table_name, {}, (err, res) ->
    if err
      console.log err
      channel.send response + "error getting award holders."
      return
    for item in res.items
      response += "#{awards[item.award]}: @#{user_ids[item.holder_id]}\n"
    channel.send response
    console.log "no error in scanning. sending response: ", response

