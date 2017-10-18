#require "hbhttpd"

REQUEST DBFCDX

MEMVAR server, cookie, session

PROCEDURE Main()

   LOCAL oServer, hConfig
   LOCAL json, itm

   LOCAL oLogAccess
   LOCAL oLogError

   IF hb_argCheck( "help" )
      ? "Usage: app [options]"
      ? "Options:"
      ? "  //help               Print help"
      ? "  //stop               Stop running server"
      RETURN
   ENDIF

   IF hb_argCheck( "stop" )
      hb_MemoWrit( ".uhttpd.stop", "" )
      RETURN
   ELSE
      hb_vfErase( ".uhttpd.stop" )
   ENDIF

   rddSetDefault( "DBFCDX" )

   IF hb_dbExists( "heroes.dbf" )
      hb_dbDrop( "heroes.dbf", "heroes.cdx" )
   ENDIF

   dbCreate( "heroes.dbf", { { "id", "I", 4, 0 }, { "name", "C", 40, 0 } }, , .T., "heroes" )

#pragma __stream | json := %s
[
    { "id": 0,  "name": "Zero" },
    { "id": 11, "name": "Mr. Nice" },
    { "id": 12, "name": "Narco" },
    { "id": 13, "name": "Bombasto" },
    { "id": 14, "name": "Celeritas" },
    { "id": 15, "name": "Magneta" },
    { "id": 16, "name": "RubberMan" },
    { "id": 17, "name": "Dynama" },
    { "id": 18, "name": "Dr IQ" },
    { "id": 19, "name": "Magma" },
    { "id": 20, "name": "Tornado" },
    { "id": 21, "name": "Juana La Cubana" }
]
ENDTEXT

   FOR EACH itm IN hb_JSONDecode( json )
      dbAppend()
      FIELD->id := itm[ "id" ]
      FIELD->name := itm[ "name" ]
   NEXT
   ordCreate( "heroes.cdx", "id", "id" )
   dbCloseArea()

   oLogAccess := UHttpdLog():New( "heroes_access.log" )

   IF ! oLogAccess:Add( "" )
      oLogAccess:Close()
      ? "Access log file open error", hb_ntos( FError() )
      RETURN
   ENDIF

   oLogError := UHttpdLog():New( "heroes_error.log" )

   IF ! oLogError:Add( "" )
      oLogError:Close()
      oLogAccess:Close()
      ? "Error log file open error", hb_ntos( FError() )
      RETURN
   ENDIF

   oServer := UHttpdNew()

   hConfig := { ;
      "FirewallFilter"      => "", ;
      "LogAccess"           => {| m | oLogAccess:Add( m + hb_eol() ) }, ;
      "LogError"            => {| m | oLogError:Add( m + hb_eol() ) }, ;
      "Trace"               => {| ... | QOut( ... ) }, ;
      "Port"                => 8002, ;
      "Idle"                => {| o | iif( hb_vfExists( ".uhttpd.stop" ), ( hb_vfErase( ".uhttpd.stop" ), o:Stop() ), NIL ) }, ;
      "SupportedMethods"    => { "GET", "POST", "OPTIONS", "PUT", "DELETE" }, ;
      "Mount"          => { ;
      "/hello"            => {|| UWrite( "Hello!" ) }, ;
      "/info"             => {|| UProcInfo() }, ;
      "/files/*"          => {| x | QOut( hb_DirBase() + "files/" + X ), UProcFiles( hb_DirBase() + "files/" + X, .F. ) }, ;
      "/api/heroes"       => @proc_heroes(), ;
      "/api/heroes/*"     => @proc_heroeById(), ;
      "/app/main"         => @proc_main(), ;
      "/"                 => {|| URedirect( "/app/main" ) } } }

   ? "Listening on port:", hConfig[ "Port" ]

   IF ! oServer:Run( hConfig )
      oLogError:Close()
      oLogAccess:Close()
      ? "Server error:", oServer:cError
      ErrorLevel( 1 )
      RETURN
   ENDIF

   oLogError:Close()
   oLogAccess:Close()

   RETURN

STATIC FUNCTION proc_main()
RETURN "Server Heroes running..."

STATIC FUNCTION proc_heroes()
   LOCAL json
   LOCAL aHeroes
   LOCAL id

   USessionStart()

   server[ "CONTENT_TYPE" ] := "application/json" /* */
   server[ "ADD_HEADERS" ] := ; /* required to properly set CORS requeriments ( request to another http provider inside Angular HTTP server ) */
   { ;
      "Access-Control-Allow-Origin" => "*", ;
      "Access-Control-Allow-Methods" => "PUT", ;
      "Access-Control-Allow-Headers" => "content-type" ;
   }

   dbUseArea( .T., , "heroes", , .T. )
   ordSetFocus( "id" )

   SWITCH server[ "REQUEST_METHOD" ]
   CASE "GET"
      aHeroes := {}
      dbEval( {|| aAdd( aHeroes, { "id" => FIELD->id, "name" => rTrim( FIELD->name ) } ) } )
      json := hb_jsonEncode( aHeroes )
      EXIT
   CASE "POST"
      dbGoBottom()
      id := FIELD->id + 1
      APPEND BLANK
      FIELD->id := id
      FIELD->name := hb_JSONDecode( server[ "BODY_RAW" ] )[ "name" ]
      dbUnLock()
      json := hb_jsonEncode( { "id" => FIELD->id, "name" => rTrim( FIELD->name ) } )
      EXIT
   ENDSWITCH

   dbCloseArea()

RETURN json

STATIC FUNCTION proc_heroeById()
   LOCAL filter
   LOCAL aHeroes
   LOCAL json
   LOCAL id
   LOCAL itm

   USessionStart()

   server[ "CONTENT_TYPE" ] := "application/json" /* */
   server[ "ADD_HEADERS" ] := ; /* required to properly set CORS requeriments ( request to another http provider inside Angular HTTP server ) */
   { ;
      "Access-Control-Allow-Origin" => "*", ;
      "Access-Control-Allow-Methods" => "PUT,DELETE", ;
      "Access-Control-Allow-Headers" => "content-type" ;
   }

   id := val( subStr( server[ "REQUEST_URI" ], hb_rat( "/", server[ "REQUEST_URI" ] ) + 1 ) )

   dbUseArea( .T., , "heroes", , ! server[ "REQUEST_METHOD" ] == "DELETE" ) /* DELETE requires EXCLUSIVE use of database */
   ordSetFocus( "id" )

   SWITCH server[ "REQUEST_METHOD" ]
   CASE "GET"
      IF hb_hHasKey( server[ "QUERY_HEADER_LIST" ], "name" ) /* handles query requests, return array of matched records */
         filter := {|| upper( server[ "QUERY_HEADER_LIST"][ "name" ] ) $ upper( FIELD->name ) }
         aHeroes := {}
         dbEval( {|| aAdd( aHeroes, { "id" => FIELD->id, "name" => rTrim( FIELD->name ) } ) }, filter )
         json := hb_jsonEncode( aHeroes )
      ELSE
         dbSeek( id )
         json := hb_jsonEncode( { "id" => FIELD->id, "name" => rTrim( FIELD->name ) } ) /* return requested 'id' */
      ENDIF
      EXIT
   CASE "PUT"
      IF dbSeek( id ) .AND. rlock()
         FOR EACH itm IN hb_JSONDecode( server[ "BODY_RAW" ] ) /* record changed on body as json */
            fieldBlock( itm:__enumKey ):eval( itm:__enumValue )
         NEXT
         dbUnLock()
      ENDIF
      EXIT
   CASE "DELETE"
      IF dbSeek( id )
         dbDelete()
         PACK
      ENDIF
      EXIT
   ENDSWITCH

   dbCloseArea()

RETURN json
