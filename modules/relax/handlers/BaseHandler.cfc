/**
********************************************************************************
Copyright 2005-2007 by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************
*/
component{

	// DI
	property name="settings" inject="coldbox:setting:relax";

	/**
	* Pre handler
	*/
	function preHandler( event, rc, prc ){
		// module root
		prc.root = event.getModuleRoot();
		// settings
		prc.settings = variables.settings;
		// exit handlers
		prc.xehHome 		= "relax/home";
		prc.xehRelax		= "relax/home.relax";
		prc.xehRelaxer		= "relax/home.relaxer";
		prc.xehDSLDocs		= "relax/home.DSLDocs";
	}

}