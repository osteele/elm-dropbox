module Dropbox
    exposing
        ( Auth
        , AuthorizeRequest
        , DownloadResponse
        , UploadResponse
        , authFromLocation
        , authorizationUrl
        , authorize
        , download
        , program
        , tokenRevoke
        , upload
        )

{-|


## Dropbox API

See the official Dropbox documentation at
<https://www.dropbox.com/developers/documentation/http/documentation>


### Authorization

@docs AuthorizeRequest, authFromLocation, authorize


### Auth

@docs tokenRevoke


### Files

@docs download, upload

-}

import Dict
import Html exposing (Html)
import Http
import Json.Decode
import Json.Encode
import Navigation
import Update.Extra


{-| Request parameters for Dropbox OAuth 2.0 authorization requests.

See <https://www.dropbox.com/developers/documentation/http/documentation#oauth2-authorize>

-}
type alias AuthorizeRequest =
    { clientId : String
    , redirectUri : String
    }


{-| Create a `AuthorizeRequest` from a `Navigation.Location`. This can be used
with `Navigation.program` to automatically generate the redirectUri from the
current page's URL.
-}
authFromLocation : String -> Navigation.Location -> AuthorizeRequest
authFromLocation clientId location =
    { clientId = clientId
    , redirectUri =
        location.protocol
            ++ "//"
            ++ location.host
            ++ location.pathname
    }


type alias Auth =
    { accessToken : String
    , tokenType : String
    , uid : String
    , accountId : String
    }


{-| The Dropbox OAuth 2.0 authorization URL.
Typically you will just want to use `authorize` instead,
which will initiate the authorization.

See <https://www.dropbox.com/developers/reference/oauth-guide>

-}
authorizationUrl : AuthorizeRequest -> String
authorizationUrl request =
    String.concat
        [ "https://www.dropbox.com/oauth2/authorize"
        , "?"
        , "response_type=token"
        , "&"
        , "client_id="
        , request.clientId
        , "&"
        , "redirect_uri="
        , request.redirectUri
        ]


{-| <https://www.dropbox.com/developers/documentation/http/documentation#oauth2-authorize>
-}
authorize : AuthorizeRequest -> Cmd msg
authorize request =
    Navigation.load <|
        authorizationUrl request


parseAuth : Navigation.Location -> Maybe Auth
parseAuth location =
    let
        isKeyValue list =
            case list of
                [ k, v ] ->
                    Just ( k, v )

                _ ->
                    Nothing

        makeAuth dict =
            Maybe.map4 Auth
                (Dict.get "access_token" dict)
                (Dict.get "token_type" dict)
                (Dict.get "uid" dict)
                (Dict.get "account_id" dict)
    in
    case String.uncons location.hash of
        Just ( '#', hash ) ->
            hash
                |> String.split "&"
                |> List.map (String.split "=")
                |> List.filterMap isKeyValue
                |> Dict.fromList
                |> makeAuth

        _ ->
            Nothing


tokenRevoke : Auth -> Http.Request ()
tokenRevoke auth =
    let
        url =
            "https://api.dropboxapi.com/2/auth/token/revoke"

        parse response =
            Ok ()
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.accessToken)
            ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectStringResponse parse
        , timeout = Nothing
        , withCredentials = False
        }


type alias DownloadResponse =
    { content : String }


download : Auth -> { filename : String } -> Http.Request DownloadResponse
download auth info =
    let
        url =
            "https://content.dropboxapi.com/2/files/download"

        parse response =
            Ok { content = response.body }

        dropboxArg =
            Json.Encode.encode 0 <|
                Json.Encode.object
                    [ ( "path", Json.Encode.string info.filename ) ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.accessToken)
            , Http.header "Dropbox-API-Arg" dropboxArg
            ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectStringResponse parse
        , timeout = Nothing
        , withCredentials = False
        }


type alias UploadResponse =
    {}


type alias UploadRequest =
    { filename : String
    , content : String
    }


upload : Auth -> UploadRequest -> Http.Request UploadResponse
upload auth info =
    let
        url =
            "https://content.dropboxapi.com/2/files/upload"

        body =
            Http.stringBody "application/octet-stream" info.content

        decoder =
            Json.Decode.succeed {}

        dropboxArg =
            Json.Encode.encode 0 <|
                Json.Encode.object
                    [ ( "path", Json.Encode.string info.filename ) ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ auth.accessToken)
            , Http.header "Dropbox-API-Arg" dropboxArg
            ]
        , url = url
        , body = body
        , expect = Http.expectJson decoder
        , timeout = Nothing
        , withCredentials = False
        }


program :
    { init : Navigation.Location -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Html msg
    , onAuth : Auth -> msg
    }
    -> Program Never model (Maybe msg)
program config =
    Navigation.program (always Nothing)
        { init =
            \location ->
                case parseAuth location of
                    Nothing ->
                        config.init location
                            |> Update.Extra.mapCmd Just

                    Just auth ->
                        config.init location
                            |> Update.Extra.andThen
                                config.update
                                (config.onAuth auth)
                            |> Update.Extra.mapCmd Just
        , update =
            \msg model ->
                case msg of
                    Nothing ->
                        ( model, Cmd.none )

                    Just m ->
                        config.update m model
                            |> Update.Extra.mapCmd Just
        , subscriptions = \_ -> Sub.none
        , view = config.view >> Html.map Just
        }
