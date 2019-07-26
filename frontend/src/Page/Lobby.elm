module Page.Lobby exposing (Model, Msg, init, subscriptions, update, view)

import Browser
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Generated.Api as BE
import Html as H
import Html.Attributes as HA
import Html.Attributes.Aria as HAA
import Html.Events as HE
import Http
import List.Nonempty as NEL
import Page
import RemoteData exposing (RemoteData)
import Result
import Route
import Session
import Task
import Time
import Utils exposing (disabledIfLoading, maybe, maybeToList, remoteDataError)


type Msg
    = NoOp
    | SetNewLine String
    | Tick Time.Posix
    | SubmitNewLine
    | HandleNewLineResp (Result Http.Error ())
    | HandleListResp (Result Http.Error (List BE.ChatLine))
    | MakeNewGame
    | HandleNewGameResp (Result Http.Error BE.GameId)


type alias Model =
    { lastUpdated : Maybe Time.Posix
    , newChatLine : String
    , chatLines : List BE.ChatLine
    , chatListError : Maybe String
    , validationIssues : List String
    , newLineSubmission : RemoteData String ()
    , newGameSubmission : RemoteData String BE.GameId
    }


type alias PageMsg =
    Page.SubMsg Msg


init : Nav.Key -> Session.User -> ( Model, Cmd PageMsg )
init key user =
    ( { newChatLine = ""
      , lastUpdated = Nothing
      , chatLines = []
      , chatListError = Nothing
      , validationIssues = []
      , newLineSubmission = RemoteData.NotAsked
      , newGameSubmission = RemoteData.NotAsked
      }
    , Task.perform (Page.wrapChildMsg Tick) Time.now
    )


subscriptions : Session.User -> Model -> Sub PageMsg
subscriptions _ _ =
    Time.every 5000 (Page.wrapChildMsg Tick)


update : Nav.Key -> Session.User -> Msg -> Model -> ( Model, Cmd PageMsg )
update key user msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        SetNewLine l ->
            ( { model | newChatLine = l }, Cmd.none )

        SubmitNewLine ->
            case validateNewChatLine user model of
                Ok newChatLine ->
                    ( { model | validationIssues = [], newLineSubmission = RemoteData.Loading }
                    , BE.postApiLobby user.token newChatLine (Page.wrapChildMsg HandleNewLineResp)
                    )

                Err problems ->
                    ( { model
                        | newLineSubmission = RemoteData.NotAsked
                        , validationIssues = problems
                      }
                    , Cmd.none
                    )

        Tick time ->
            ( model
            , BE.getApiLobby
                user.token
                (model.chatLines |> List.map (.chatLineTime >> Time.posixToMillis) |> List.maximum)
                (Page.wrapChildMsg HandleListResp)
            )

        HandleListResp (Err e) ->
            ( { model | chatListError = Just (Utils.httpErrorToStr e) }, Cmd.none )

        HandleListResp (Ok l) ->
            ( { model
                | chatListError = Nothing
                , chatLines =
                    if model.chatLines == [] then
                        l

                    else
                        model.chatLines ++ l
              }
            , jumpToChatBottom
            )

        HandleNewLineResp r ->
            let
                remoteData =
                    RemoteData.fromResult r
                        |> RemoteData.mapError Utils.httpErrorToStr
            in
            ( { model | newLineSubmission = remoteData, newChatLine = "" }
            , RemoteData.unwrap
                Cmd.none
                (\us -> Task.perform (Page.wrapChildMsg Tick) Time.now)
                remoteData
            )

        MakeNewGame ->
            ( { model | newGameSubmission = RemoteData.Loading }
            , BE.postApiGame user.token (Page.wrapChildMsg HandleNewGameResp)
            )

        HandleNewGameResp r ->
            let
                remoteData =
                    RemoteData.fromResult r
                        |> RemoteData.mapError Utils.httpErrorToStr
            in
            ( { model | newGameSubmission = remoteData }
            , RemoteData.unwrap
                Cmd.none
                (\gId -> Route.pushRoute key (Route.Game gId))
                remoteData
            )


jumpToChatBottom : Cmd PageMsg
jumpToChatBottom =
    Dom.getViewportOf "chatbox"
        |> Task.andThen (\info -> Dom.setViewportOf "chatbox" 0 info.scene.height)
        |> Task.attempt (\_ -> Page.ChildMsg NoOp)



-- elm-verify is a much better way of doing this. But this is our only validation.
-- Come back to this later.


validateNewChatLine : Session.User -> Model -> Result.Result (List String) String
validateNewChatLine user model =
    let
        trimmedLine =
            String.trim model.newChatLine

        newChatLineError =
            if trimmedLine == "" then
                [ "Message cannot be blank" ]

            else
                []

        allErrs =
            List.concat [ newChatLineError ]
    in
    if allErrs == [] then
        Result.Ok trimmedLine

    else
        Result.Err allErrs


view : Model -> Browser.Document Msg
view model =
    { title = "Dissidence - Lobby"
    , body =
        [ H.div [ HA.class "chatbox-container" ]
            [ H.h1 [] [ H.text "Lobby" ]
            , H.div [ HA.id "chatbox", HA.class "chatbox" ] (List.map chatLineView model.chatLines)
            , H.form [ HE.onSubmit SubmitNewLine ]
                [ H.ul []
                    [ H.li [ HA.class "chat-message" ]
                        [ H.input
                            [ HA.placeholder "type a chat message"
                            , HE.onInput SetNewLine
                            , HA.value model.newChatLine
                            , HA.class "chat-message-input"
                            , HAA.ariaLabel "Enter Chat Message"
                            ]
                            []
                        ]
                    , H.li []
                        [ H.button
                            [ HA.class "btn primary", disabledIfLoading model.newLineSubmission ]
                            [ H.text "send" ]
                        ]
                    , let
                        errorsMay =
                            NEL.fromList (maybeToList (remoteDataError model.newLineSubmission) ++ model.validationIssues)
                      in
                      Utils.maybe (H.text "") chatWarnings errorsMay
                    ]
                ]
            ]
        , H.div []
            [ H.button [ HE.onClick MakeNewGame ] [ H.text "New Game" ]
            ]
        ]
    }


chatWarnings : NEL.Nonempty String -> H.Html Msg
chatWarnings errors =
    H.li [ HA.class "chat-warnings" ] [ H.ul [ HA.class "warn" ] (List.map (\em -> H.li [] [ H.text em ]) (NEL.toList errors)) ]


chatLineView : BE.ChatLine -> H.Html Msg
chatLineView cl =
    H.p []
        [ H.b [] [ H.text cl.chatLineUsername, H.text "> " ]
        , H.text cl.chatLineText
        ]
