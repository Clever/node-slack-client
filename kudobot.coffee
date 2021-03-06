# This is the file that runs kudobot. Sorry that it's not on master. I was a git noob when I created this -Potluck
# To deploy, run fab mesos.apps.deploy:node-slack-client,env=production,version=SANHAXISCO-30-kudobot

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
godUsers = ["@jam", "@potluck", "@cort"]

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
  try
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
      if words[0] is "set" and words.length > 2
        if userName not in godUsers
          bad_set_permissions channel
          return
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
      else if text.indexOf("nominate") is 0 and words.length >= 4
        award = words[2]
        if award[0] is '[' and award[award.length-1] is ']'
          award = award.substring(1, award.length-1)
          words[2] = award
        if not awards[award]?
          bad_nomination channel
        else
          jam_pot_notif words, userName
          # holder_notif calls good_nomination to respond to the nominater
          holder_notif words, userName, channel
          team_notif award


      else
        bad_nomination channel

    else
      typeError = if type isnt 'message' then "unexpected type #{type}." else null
      textError = if not text? then 'text was undefined.' else null
      undefChannelError = if not channel? then 'channel was undefined.' else null
      channelError = if channel?.is_channel then 'post in public channel' else null
      kudobotCase = if userName is "@kudobot" then 'Kudobot posted the message' else null

      errors = [typeError, textError, undefChannelError, channelError, kudobotCase].filter((element) -> element isnt null).join ' '

      console.error """
        @#{slack.self.name} could not respond. #{errors}
      """
  catch error
    console.error "Error: #{error.stack}"


slack.on 'error', (error) -> console.error "Error: #{error}"


slack.login()

# For Jamila/Potluck/Cort to set who is the current holder of the award
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

bad_set_permissions = (channel) ->
  response = "You don't have sufficient permissions to use `set` - please send #oncall-ip a message if you believe this is an error.\n"
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

# notifies the holder of the award that the nomination was made
# takes in channel so that it can call good_nomination
holder_notif = (words, userName, channel) ->
  award = words[2]
  holder_msg = "Hey! "+ userName+" made a nomination!\n"
  holder_msg += words[1] + " has been nominated for " + award
  holder_msg += " for " + words.slice(3).join(' ') + "\n"

  ddb.getItem table_name, award, null, {}, (err, res, cap) ->
    if err
      console.log err
      issue_notifying_holder channel
      return
    holder_id = res.holder_id
    slack.openDM holder_id, (value) ->
      holder_dm_id = value.channel.id
      holder_dm = slack.getDMByID(holder_dm_id)
      holder_dm.send holder_msg
      good_nomination channel, holder_id

issue_notifying_holder = (channel) ->
  msg = "Unfortunately, there was an issue notifying the holder of the kudo. Sorry! Please let Potluck know " +
    "this happened, and either message the award holder directly, or try sending in the nomination again."
  channel.send msg

jam_pot_notif = (words, userName) ->
  award = words[2]
  jamila_msg = "Hey Jamila/Potluck, "+ userName+" made a nomination!\n"
  jamila_msg += words[1] + " has been nominated for " + award
  jamila_msg += " for " + words.slice(3).join(' ') + "\n"
  jamila_dm.send jamila_msg
  potluck_dm.send jamila_msg

good_nomination = (channel, holder_id) ->
  response = "Great! @#{user_ids[holder_id]} has been notified of this nomination."
  channel.send response

bad_nomination = (channel) ->
  response = "Usage: `nominate [nominee] [award] [reason]`\n"
  response += "`nominee` should be a single word name\n"
  response += "`award` should be one of: `credit`, `vibes`, `student`, `group`, `classroom`, `textbook`, `cleaver` or `security`\n"
  response += "`reason` should be a non-empty description\n"
  response += "Current Award holders are: \n"

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

