#
# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license.
#
# Description:
#   Middleware to make Hubot work well with Microsoft Teams
#
# Configuration:
#	HUBOT_OFFICE365_TENANT_FILTER
#
# Commands:
#	None
#
# Notes:
#   1. Typing indicator support
#   2. Properly converts Slack @mentions to Teams @mentions
#   3. Properly handles chat vs. channel messages
#   4. Optionally filters out messages from outside the tenant
#   5. Properly handles image responses.
#
# Author:
#	billbliss
#

MicrosoftGraph = require '@microsoft/microsoft-graph-client'
{ Robot, TextMessage, Message, User } = require 'hubot'
{ BaseMiddleware, registerMiddleware } = require './adapter-middleware'
LogPrefix = "hubot-msteams:"

class MicrosoftTeamsMiddleware extends BaseMiddleware
    constructor: (@robot) ->
        super(@robot)

        @allowedTenants = []
        if process.env.HUBOT_OFFICE365_TENANT_FILTER?
            @allowedTenants = process.env.HUBOT_OFFICE365_TENANT_FILTER.split(",")
            @robot.logger.info("#{LogPrefix} Restricting tenants to #{JSON.stringify(@allowedTenants)}")

    toReceivable: (activity) ->
        @robot.logger.info "#{LogPrefix} toReceivable"

        # Store the current user's aadObjectId

        # Drop the activity if it came from an unauthorized tenant
        if @allowedTenants.length > 0 && !@allowedTenants.includes(getTenantId(activity))
            @robot.logger.info "#{LogPrefix} Unauthorized tenant; ignoring activity"
            return null
        
        console.log("Checking booleans:----------------------------")
        console.log(@robot.brain.get("admins"))

        # Drop the activity if this user isn't authorized to send commands
        # Ignores unauthorized commands for now, may change to display error message
        authorizedUsers = @robot.brain.get("authorizedUsers")
        if authorizedUsers && authorizedUsers.length > 0 && !authorizedUsers.includes(getUserAadObjectId(activity))
           @robot.logger.info "#{LogPrefix} Unauthorized user; ignoring activity"
           return null

        # Get the user
        user = getUser(activity)
        user = @robot.brain.userForId(user.id, user)

        # We don't want to save the activity or room in the brain since its something that changes per chat.
        user.activity = activity
        user.room = getRoomId(activity)

        if activity.type == 'message'
            activity = fixActivityForHubot(activity, @robot)
            message = new TextMessage(user, activity.text, activity.address.id)
            return message

        return new Message(user)

    toSendable: (context, message) ->
        @robot.logger.info "#{LogPrefix} toSendable"
        activity = context?.user?.activity

        response = message
        if typeof message is 'string'
            response =
                type: 'message'
                text: message
                address: activity?.address
            
            imageAttachment = convertToImageAttachment(message)
            if imageAttachment?
                card = {
                    'contentType': 'application/vnd.microsoft.card.adaptive',
                    'content': {
                        '$schema': 'http://adaptivecards.io/schemas/adaptive-card.json',
                        'type': 'AdaptiveCard',
                        'version': '1.0',
                        'body': [
                            {
                                'type': 'Container',
                                'speak': '<s>Hello!</s><s>Are you looking for a flight or a hotel?</s>',
                                'items': [
                                    {
                                        'type': 'ColumnSet',
                                        'columns': [
                                            # {
                                            #     'type': 'Column',
                                            #     'size': 'auto',
                                            #     'items': [
                                            #         {
                                            #             'type': 'Image',
                                            #             'url': 'https://placeholdit.imgix.net/~text?txtsize=65&txt=Adaptive+Cards&w=300&h=300',
                                            #             'size': 'medium',
                                            #             'style': 'person'
                                            #         }
                                            #     ]
                                            # },
                                            {
                                                'type': 'Column',
                                                'size': 'stretch',
                                                'items': [
                                                    {
                                                        'type': 'TextBlock',
                                                        'text': 'Hello!',
                                                        'weight': 'bolder',
                                                        'isSubtle': true
                                                    },
                                                    {
                                                        'type': 'TextBlock',
                                                        'text': 'Are you looking for a flight or a hotel?',
                                                        'wrap': true
                                                    }
                                                ]
                                            }
                                        ]
                                    }
                                ]
                            }
                        ],
                        'actions': [
                        # Hotels Search form
                            {
                                'type': 'Action.ShowCard',
                                'title': 'Hotels',
                                'speak': '<s>Hotels</s>',
                                'card': {
                                    'type': 'AdaptiveCard',
                                    'body': [
                                        {
                                            'type': 'TextBlock',
                                            'text': 'Welcome to the Hotels finder!',
                                            'speak': '<s>Welcome to the Hotels finder!</s>',
                                            'weight': 'bolder',
                                            'size': 'large'
                                        },
                                        {
                                            'type': 'TextBlock',
                                            'text': 'Please enter your destination:'
                                        },
                                        {
                                            'type': 'Input.Text',
                                            'id': 'destination',
                                            'speak': '<s>Please enter your destination</s>',
                                            'placeholder': 'Miami, Florida',
                                            'style': 'text'
                                        },
                                        {
                                            'type': 'TextBlock',
                                            'text': 'When do you want to check in?'
                                        },
                                        {
                                            'type': 'Input.Date',
                                            'id': 'checkin',
                                            'speak': '<s>When do you want to check in?</s>'
                                        },
                                        {
                                            'type': 'TextBlock',
                                            'text': 'How many nights do you want to stay?'
                                        },
                                        {
                                            'type': 'Input.Number',
                                            'id': 'nights',
                                            'min': 1,
                                            'max': 60,
                                            'speak': '<s>How many nights do you want to stay?</s>'
                                        }
                                    ],
                                    'actions': [
                                        {
                                            'type': 'Action.Submit',
                                            'title': 'Search',
                                            'speak': '<s>Search</s>',
                                            'data': {
                                                'text': "#{response.text}",
                                                'type': 'hotelSearch'
                                            }
                                        }
                                    ]
                                }
                            },
                            {
                                'type': 'Action.ShowCard',
                                'title': 'Flights',
                                'speak': '<s>Flights</s>',
                                'card': {
                                    'type': 'AdaptiveCard',
                                    'body': [
                                        {
                                            'type': 'TextBlock',
                                            'text': 'Flights is not implemented =(',
                                            'speak': '<s>Flights is not implemented</s>',
                                            'weight': 'bolder'
                                        }
                                    ]
                                }
                            }
                        ]
                    }
                };

                delete response.text
                #response.attachments = [imageAttachment]
                response.attachments = [card]

        response = fixMessageForTeams(response, @robot)

        typingMessage =
          type: "typing"
          address: activity?.address

        return [typingMessage, response]

    #############################################################################
    # Helper methods for generating richer messages
    #############################################################################

    imageRegExp = /^(https?:\/\/.+\/(.+)\.(jpg|png|gif|jpeg$))/

    # Generate an attachment object from the first image URL in the message
    convertToImageAttachment = (message) ->
        if not typeof message is 'string'
            return null

        result = imageRegExp.exec(message)
        if result?
            attachment =
                contentUrl: result[1]
                name: result[2]
                contentType: "image/#{result[3]}"
            return attachment

        return null
        
    # Fetches the user object from the activity
    getUser = (activity) ->
        user =
            id: activity?.address?.user?.id,
            name: activity?.address?.user?.name,
            tenant: getTenantId(activity)
            aadObjectId: getUserAadObjectId(activity)
        return user
    
    # Fetches the user's name from the activity
    getUserName = (activity) ->
        return activity?.address?.user?.name

    # Fetches the user's AAD Object Id from the activity
    getUserAadObjectId = (activity) ->
        console.log("HIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII")
        blah = "aaaa-blah"
        activity?.address?.user[blah] =
            first: "does this work"
            second: "yup"
        console.log(activity?.address?.user[blah].zero == undefined)
        console.log(activity?.address?.user[blah].first)
        console.log(activity?.address?.user[blah].second)

        return activity?.address?.user?.aadObjectId

    # Fetches the room id from the activity
    getRoomId = (activity) ->
        return activity?.address?.conversation?.id

    # Fetches the tenant id from the activity
    getTenantId = (activity) ->
        return activity?.sourceEvent?.tenant?.id

    # Returns the array of mentions that can be found in the message.
    getMentions = (activity, userId) ->
        entities = activity?.entities || []
        if not Array.isArray(entities)
            entities = [entities]
        return entities.filter((entity) -> entity.type == "mention" && (not userId? || userId == entity.mentioned?.id))

    # Fixes the activity to have the proper information for Hubot
    # 1. Replaces all occurances of the channel's bot at mention name with the configured name in hubot.
    #  The hubot's configured name might not be the same name that is sent from the chat service in
    #  the activity's text.
    # 2. Prepends hubot's name to the message if this is a direct message.
    fixActivityForHubot = (activity, robot) ->
        if not activity?.text? || typeof activity.text isnt 'string'
            return activity
        myChatId = activity?.address?.bot?.id
        if not myChatId?
            return activity

        # replace all @ mentions with the robot's name
        mentions = getMentions(activity)
        for mention in mentions
            mentionTextRegExp = new RegExp(escapeRegExp(mention.text), "gi")
            replacement = mention.mentioned.name
            if mention.mentioned.id == myChatId
                replacement = robot.name

            activity.text = activity.text.replace(mentionTextRegExp, replacement)

        # prepends the robot's name for direct messages
        roomId = getRoomId(activity)
        if roomId? and not roomId.startsWith("19:") and not activity.text.startsWith(robot.name)
            activity.text = "#{robot.name} #{activity.text}"

        # remove the newline character at the beginning or end of the text
        # if there are any
        if activity.text.charAt(activity.text.length - 1) == '\n'
            activity.text = activity.text.trim()
        console.log(activity.text)
            
        return activity

    slackMentionRegExp = /<@([^\|>]*)\|?([^>]*)>/g

    # Fixes the response to have the proper information that teams needs
    # 1. Replaces all slack @ mentions with Teams @ mentions
    #  Slack mentions take the form of <@[username or id]|[mention text]>
    #  We have to convert this into a mention object which needs the id.
    fixMessageForTeams = (response, robot) ->
        if not response?.text?
            return response

        mentions = []
        while match = slackMentionRegExp.exec(response.text)
            foundUser = null
            users = robot.brain.users()
            for userId, user of users
                if userId == match[1] || user.name == match[1]
                    foundUser = user

            userId = foundUser?.id || match[1]
            userName = foundUser?.name || match[1]
            userText = "<at>#{match[2] || userName}</at>"
            mentions.push(
                full: match[0]
                mentioned:
                    id: userId
                    name: userName
                text: userText
                type: "mention")
        
        for mention in mentions
            mentionTextRegExp = new RegExp(escapeRegExp(mention.full), "gi")
            response.text = response.text.replace(mentionTextRegExp, mention.text)
            delete mention.full
        response.entities = mentions
        return response

    escapeRegExp = (str) ->
        return str.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")


registerMiddleware 'msteams', MicrosoftTeamsMiddleware

module.exports = MicrosoftTeamsMiddleware
