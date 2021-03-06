/**
 * Copyright Ortus Solutions, Corp, All rights reserved
 * www.ortussolutions.com
 * ---
 * Translator for RelaxDSL APIs in to OpenAPI Format
 *
 * @deprecated v3.0.0
 * @eol			v4.0.0
 */
component accessors="true" singleton {

	property name="wirebox" 		inject="wirebox";
	property name="SwaggerUtil" 	inject="OpenAPIUtil@SwaggerSDK";

	/**
	 * On DI Complete
	 */
	function onDIComplete(){
		// We need to use Linked Hashmaps to maintain struct order for serialization and deserialization
		variables.openAPITemplate = getSwaggerUtil().newTemplate();

		// Utility arrays for default methods and responses
		variables.HTTPMethods         = getSwaggerUtil().defaultMethods();
		variables.HTTPMethodResponses = getSwaggerUtil().defaultSuccessResponses();
	}

	/**
	 * Translates a RelaxDSL CFC in to the OpenAPI specification
	 *
	 * @param dataCFC 		The Relax.cfc object to translate
	 **/
	function translate( required any dataCFC ){
		var OpenAPIParser = getWirebox().getInstance( "OpenAPIParser@relax" );

		var translation = duplicate( variables.openAPITemplate );

		translateGlobals( arguments.dataCFC, translation );

		translatePaths( arguments.dataCFC, translation );

		return OpenAPIParser.parse( translation );
	}

	/**
	 * Translate RelaxDSL global variables in to the OpenAPI specification
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private void function translateGlobals( required any dataCFC, required translation ){
		var relax = arguments.dataCFC.relax;

		for ( var key in relax ) {
			if ( structKeyExists( translation, key ) ) translation[ key ] = relax[ key ];
			if ( structKeyExists( translation[ "info" ], key ) ) translation[ "info" ][ key ] = relax[ key ];
		}

		// Deprecated in 3
		//translateMimeTypes( dataCFC, translation );

		translateSecurityDefinitions( dataCFC, translation );

		translateURLs( dataCFC, translation );

		processGlobalExtensions( dataCFC, translation );
	}

	/**
	 * Translate RelaxDSL mimetype annotations in to full mimetype values
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private void function translateMimeTypes( required any dataCFC, required translation ){
		var relax = dataCFC.relax;

		if ( structKeyExists( relax, "validExtensions" ) ) {
			translation[ "produces" ] = listToArray( relax.validExtensions );
		}

		for ( var i = 1; i <= arrayLen( translation[ "produces" ] ); i++ ) {
			// skip valid mimetypes
			if ( listLen( translation[ "produces" ][ i ], "/" ) > 1 ) continue;

			if ( !reFindNoCase( translation[ "produces" ][ i ], "html|plain|template" ) ) {
				translation[ "produces" ][ i ] = "application/" & translation[ "produces" ][ i ];
			} else {
				translation[ "produces" ][ i ] = "text/" & translation[ "produces" ][ i ];
			}
		}
	}

	/**
	 * Translate RelaxDSL security headers in to OpenAPI security definitions
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private void function translateSecurityDefinitions( required any dataCFC, required translation ){
		for ( var header in dataCFC.globalHeaders ) {
			if ( !structKeyExists( translation.components, "securitySchemes" ) )
				translation.components[ "securitySchemes" ] = structNew( "ordered" );

			translation.components[ "securitySchemes" ][ header[ "name" ] ] = {
				"type"        : structKeyExists( header, "type" ) ? ( header[ "type" ] == "string" ? "http" : header[ "type" ] ) : "http",
				"name"        : header[ "name" ],
				"description" : structKeyExists( header, "description" ) ? header[ "description" ] : "",
				"in"          : "header"
			};

			// override our special type if the header value is an api key
			if ( findNoCase( header[ "name" ], "api" ) && findNocCase( header[ "nane" ], "key" ) )
				translation.components[ "securityDefinitions" ][ header[ "name" ] ].type = "apiKey";
		}
	}

	/**
	 * Translate RelaxDSL entry points in to the OpenAPI specification
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private void function translateURLs( required any dataCFC, required translation ){
		var relax = dataCFC.relax;
		if ( isSimpleValue( relax.entryPoint ) ) relax.entryPoint = { "production" : relax.entryPoint };

		for ( var key in relax.entryPoint ) {
			arrayAppend( translation[ "servers" ], {
				"url" : relax.entryPoint[ key ],
				"description" : key
			} );
		}

	}

	/**
	 * Translate RelaxDSL Coldbox attributes in to OpenAPI extensions
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private void function processGlobalExtensions( required any dataCFC, required translation ){
		var relax      = dataCFC.relax;
		var extensions = [ "extensionDetection", "throwOnInvalidExtension", "entryPoint", "validExtensions" ];

		for ( var ext in extensions ) {
			if ( structKeyExists( relax, ext ) ) {
				translation[ "x-" & trim( ext ) ] = relax[ ext ];
			}
		}
	}

	/**
	 * Translate RelaxDSL resources in to OpenAPI paths
	 * @param dataCFC 		The Relax.cfc object to translate
	 * @param translation 	The translation template to append dataCFC globals
	 **/
	private function translatePaths( required any dataCFC, required translation ){
		var resources = dataCFC.resources;

		for ( var resource in resources ) {
			var pathKey = translatePathKey( resource.pattern );
			translation[ "paths" ].put( pathkey, { "x-resourceId" : resource.resourceId } );

			translatePathMethods( translation[ "paths" ][ pathKey ], resource, translation );
		}
	}

	/**
	 * Translate RelaxDSL Coldbox routes to use OpenAPI placeholders
	 * @param pattern 		The pattern to be translated
	 **/
	private string function translatePathKey( pattern ){
		var paths = listToArray( pattern, "/" );
		for ( var i = 1; i <= arrayLen( paths ); i++ ) {
			var path = paths[ i ];
			if ( left( path, 1 ) == ":" ) {
				paths[ i ] = "{" & right( path, len( path ) - 1 ) & "}";
			}
		}

		return "/" & arrayToList( paths, "/" );
	}

	/**
	 * Translate RelaxDSL resource patterns in to OpenAPI path methods
	 * @param path 			The path struct to be appended
	 * @param resource 		The RelaxDSL resource to be translated
	 * @param translation 	The top-level translation object - used as a reference for params
	 **/
	private void function translatePathMethods( required struct path, required struct resource, required translation ){
		var pathKey = translatePathKey( resource.pattern );

		// handle string action values for consistent formatting
		if ( isSimpleValue( resource.action ) ) {
			resource.handlerMethod = resource.action;
			resource.action        = structNew( "ordered" );
			resource.action.put( resource.defaultMethod, resource.action );

			var allowedMethods = listToArray( resource.methods );

			for ( var method in allowedMethods ) {
				if ( method != resource.defaultMethod ) {
					resource.action.put( method, resource.action[ resource.defaultMethod ] );
				}
			}

		}

		// assembly begins
		for ( var HTTPMethod in resource.action ) {
			if (
				!findNoCase( "x-", HTTPMethod )
				 &&
				structKeyExists( resource, "handlerMethod" )
				 &&
				isSimpleValue( resource.handlerMethod )
				 &&
				len( resource.handlerMethod )
				 &&
				!isStruct( resource.handlerMethod )
			) {
				var operationalAction = "." & resource.handlerMethod;
			} else {
				var operationalAction = "";
			}

			path.put(
				lCase( HTTPMethod ),
				{
					"description" : structKeyExists( resource, "description" ) ? resource.description : "",
					"operationId" : resource.handler & operationalAction,
					"responses"   : structNew( "ordered" ),
					"parameters"  : [],
					"x-resourceId" : lCase( hash( pathKey & lCase( HTTPMethod ) ) ),
					"x-coldbox-handler" : resource.handler
				}
			);

			if ( !len( trim( path[ lCase( HTTPMethod ) ][ "operationId" ] ) ) ) {
				structDelete( path[ lCase( HTTPMethod ) ], "operationId" );
			}


			// handle our URL placeholders
			for ( var placeholder in resource.placeholders ) {
				path[ lCase( HTTPMethod ) ][ "parameters" ].append(
					{
						"name"				: placeholder.name,
						"in"          		: "path",
						"description" 		: ( structKeyExists( placeholder, "description" ) ? placeholder.description : "" ),
						"required"    		: javacast( "boolean", placeholder.required ),
						"type"        		: structKeyExists( placeholder, "type" ) ? placeholder.type : "string",
						"x-defaultValue" 	: structKeyExists( placeholder, "defaultValue" ) ? placeholder.defaultValue : ""
					}
				);
			}
		}

		// append parameter information to our paths
		processPathParameters( path, resource );

		// append schema as responses
		processPathSchemas( path, resource );

		// append samples as extended attributes Doesn't exist anymore
		//processPathSamples( path, resource );
	}

	/**
	 * Processes RelaxDSL resource parameters
	 * @param path 			The OpenAPI doc path to append the params
	 * @param resource 		The RelaxDSL resource
	 **/
	private function processPathParameters( required path, resource ){
		for ( var param in resource[ "parameters" ] ) {
			var appendTo = [];
			for ( var method in variables.HTTPMethods ) {
				if ( findNoCase( " " & method & " ", param.description ) ) {
					arrayAppend( appendTo, method );
				}
			}
			// append to all if we didn't find an HTTP method reference
			if ( !arrayLen( appendTo ) ) appendTo = variables.HTTPMethods;

			for ( var method in appendTo ) {
				if ( structKeyExists( path, lCase( method ) ) ) {
					path[ lCase( method ) ][ "parameters" ].append(
						{
							"name"			: param.name,
							"in"          	: ( method == "GET" ? "query" : "formData" ),
							"description" 	: ( structKeyExists( param, "description" ) ? param.description : "" ),
							"required"    	: javacast( "boolean", param.required ),
							"type"        	: param.type
						}
					);
				}
			}
		}
	}

	/**
	 * Processes RelaxDSL resource schemas
	 * @param path 			The OpenAPI doc path to append the schemas
	 * @param resource 		The RelaxDSL resource
	 **/
	private function processPathSchemas( required path, required resource ){
		if ( structKeyExists( resource.response, "schemas" ) ) {
			for ( var schema in resource.response[ "schemas" ] ) {
				// RelaxDSL doesn't provide status codes, so we'll use our defaults
				var schemaDefinition = {
					"description" : schema[ "description" ],
					"content" 	: {
					}
				};

				switch ( schema[ "format" ] ) {
					case "json":
						var body     = deserializeJSON( schema[ "body" ] );
						var mimeType = "application/json";
						break;
					case "xml":
						var body     = schema[ "body" ];
						var mimeType = "application/xml";
						break;
					default:
						var body     = schema[ "body" ];
						var mimeType = reFindNoCase( schema[ "format" ], "html|text|string" ) ? "text/" & schema[
							"format"
						] : "application/" & schema[ "format" ];
				}

				schemaDefinition[ "content" ][ mimeType ] = {
					"schema" : {
					}
				};

				for ( var methodKey in path ) {
					var methodPosition = arrayFindNoCase( variables.HTTPMethods, methodKey );
					if ( methodPosition ) {
						var statusCode = variables.HTTPMethodResponses[ methodPosition ];

						if ( !structKeyExists( path[ methodKey ][ "responses" ], statusCode ) ) {
							path[ methodKey ][ "responses" ].put( javacast( "string", statusCode ), schemaDefinition );
						} else if ( structKeyExists( path[ methodKey ][ "responses" ], statusCode ) ) {
							path[ methodKey ][ "responses" ].put( "default", schemaDefinition );
						}
					}
				}
			}
		}
	}

	/**
	 * Processes RelaxDSL samples to the paths
	 * @param path 			The OpenAPI doc path to append the samples
	 * @param resource 		The RelaxDSL resource
	 **/
	private function processPathSamples( required path, required resource ){
		if ( structKeyExists( resource.response, "samples" ) ) {
			for ( var sample in resource.response[ "samples" ] ) {
				// RelaxDSL doesn't provide status codes, so we'll use our defaults
				var sampleDefinition = {
					"description" : sample[ "description" ],
					"sample"      : { "type" : "object" },
					"examples"    : structNew( "ordered" )
				};

				switch ( sample[ "format" ] ) {
					case "json":
						var body     = deserializeJSON( sample[ "body" ] );
						var mimeType = "application/json";
						break;
					case "xml":
						var body     = sample[ "body" ];
						var mimeType = "application/xml";

						break;
					default:
						var body     = sample[ "body" ];
						var mimeType = reFindNoCase( sample[ "format" ], "html|text|string" ) ? "text/" & sample[
							"format"
						] : "application/" & sample[ "format" ];
				}


				sampleDefinition[ "examples" ].put( mimeType, body );


				for ( var methodKey in path ) {
					var methodPosition = arrayFindNoCase( variables.HTTPMethods, methodKey );
					if ( methodPosition ) {
						var statusCode = variables.HTTPMethodResponses[ methodPosition ];

						if ( !structKeyExists( path[ methodKey ], "x-request-samples" ) ) {
							path[ methodKey ].put( "x-request-samples", sampleDefinition );
						} else {
							if ( structKeyExists( path[ methodKey ][ "x-request-samples" ][ "examples" ], mimeType ) ) {
								path[ methodKey ][ "x-request-samples" ][ "examples" ].put(
									"default",
									sampleDefinition[ "examples" ][ mimeType ]
								);
							} else {
								path[ methodKey ][ "x-request-samples" ][ "examples" ].put(
									mimeType,
									sampleDefinition[ "examples" ][ mimetype ]
								);
							}
						}
					}
				}
			}
		}
	}

}
