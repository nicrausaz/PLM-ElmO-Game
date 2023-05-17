port module Game.Host exposing (..)

import Game.AI
import Game.Action exposing (Action)
import Game.Card
import Game.Color
import Game.Core
import Json.Decode as D
import Json.Encode as E
import Random
import Session exposing (Session)
import Task
import UUID
import Utils


type alias Game =
    Game.Core.Model


port outgoingData : E.Value -> Cmd msg


port incomingAction : (E.Value -> msg) -> Sub msg


type HostMsg
    = IncomingAction E.Value
    | OnAction Action
    | AITurnComplete (Result String Action)


addAIPlayersCmd : Int -> Cmd HostMsg
addAIPlayersCmd n =
    let
        toPlayerJoin ( uuid, username ) =
            Game.Action.PlayerJoin (UUID.toString uuid) username True

        generatePlayer =
            Random.pair UUID.generator Utils.randomCharacterGenerator
                |> Random.map toPlayerJoin
    in
    Random.generate OnAction (Random.list n generatePlayer |> Random.map Game.Action.Batch)


actionCmd : Action -> Cmd HostMsg
actionCmd action =
    Task.succeed (OnAction action)
        |> Task.perform identity


setHostGame : Game.Core.Model -> { a | session : Session } -> { a | session : Session }
setHostGame game model =
    case model.session.session of
        Session.Host config roomData ->
            { model | session = model.session |> Session.update (Session.Host { config | game = game } roomData) }

        _ ->
            model


getHostGame : { a | session : Session } -> Maybe Game.Core.Model
getHostGame model =
    case model.session.session of
        Session.Host config _ ->
            Just config.game

        _ ->
            Nothing


getCurrentPlayer : { a | session : Session } -> Utils.UUID
getCurrentPlayer model =
    case model.session.session of
        Session.Host _ roomData ->
            roomData.playerUUID

        Session.Client roomData ->
            roomData.playerUUID

        _ ->
            ""


update : HostMsg -> { a | session : Session } -> ( { a | session : Session }, Cmd HostMsg )
update msg model =
    case ( msg, model |> getHostGame ) of
        ( IncomingAction data, Just _ ) ->
            case D.decodeValue Game.Action.decodeAction data of
                Ok action ->
                    update (OnAction action) model

                Err _ ->
                    ( model, Cmd.none )

        ( OnAction action, Just host ) ->
            case Game.Action.executeAction action host of
                ( newHost, True ) ->
                    ( model |> setHostGame newHost, Cmd.batch [ outgoingData (encodeGame newHost), Game.AI.aiBatch AITurnComplete newHost ] )

                ( newHost, _ ) ->
                    ( model |> setHostGame newHost, Cmd.none )

        ( AITurnComplete (Ok action), Just _ ) ->
            update (OnAction action) model

        _ ->
            ( model, Cmd.none )



-- DECODERS


encodePlayer : Game.Core.Player -> E.Value
encodePlayer player =
    E.object
        [ ( "name", E.string player.name )
        , ( "uuid", E.string player.uuid )
        , ( "hand", E.list Game.Card.encodeCard player.hand )
        , ( "saidUno", E.bool player.saidUno )
        , ( "isAI", E.bool player.isAI )
        ]


encodeGame : Game -> E.Value
encodeGame game =
    E.object
        [ ( "players", E.list encodePlayer game.players )
        , ( "currentPlayer", Utils.maybeEncode E.string (Maybe.map (\p -> p.uuid) (game |> Game.Core.getCurrentPlayer |> Tuple.first)) )
        , ( "drawStack", E.int (game.drawStack |> List.length) )
        , ( "activeCard", Utils.maybeEncode Game.Card.encodeCard game.activeCard )
        , ( "activeColor", Utils.maybeEncode Game.Color.encodeColor game.activeColor )
        , ( "gameOver" , E.bool (game |> Game.Core.isGameOver))
        ]
