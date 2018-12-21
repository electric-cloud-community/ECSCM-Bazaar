@files = (
    ['//property[propertyName="ECSCM::Bazaar::Cfg"]/value',    'scm_driver/BazaarCfg.pm'],
    ['//property[propertyName="ECSCM::Bazaar::Driver"]/value', 'scm_driver/BazaarDriver.pm'],
    ['//property[propertyName="checkout"]/value',              'scm_form/checkout.xml'],
    ['//property[propertyName="preflight"]/value',             'scm_form/preflight.xml'],
    ['//property[propertyName="sentry"]/value',                'scm_form/sentry.xml'],
    ['//property[propertyName="trigger"]/value',               'scm_form/trigger.xml'],
    ['//property[propertyName="createConfig"]/value',          'scm_form/createConfig.xml'],
    ['//property[propertyName="editConfig"]/value',            'scm_form/editConfig.xml'],
    ['//property[propertyName="ec_setup"]/value',              'ec_setup.pl'],

    ['//procedure[procedureName="CheckoutCode"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'scm_form/checkout.xml'],
    ['//procedure[procedureName="Preflight"]/propertySheet/property[propertyName="ec_parameterForm"]/value',    'scm_form/preflight.xml'],
         );
