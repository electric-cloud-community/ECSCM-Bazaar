my $projPrincipal = "project: $pluginName";
my $ecscmProj     = '$[/plugins/ECSCM/project]';

if ($promoteAction eq 'promote') {

    # Register our SCM type with ECSCM
    $batch->setProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@", "Bazaar");

    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry("user", $projPrincipal, { projectName => $ecscmProj });
    if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
        $batch->createAclEntry(
                               "user",
                               $projPrincipal,
                               {
                                  projectName      => $ecscmProj,
                                  executePrivilege => "allow"
                               }
                              );
    }
}
elsif ($promoteAction eq 'demote') {

    # unregister with ECSCM
    $batch->deleteProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@");

    # remove permissions
    my $xpath = $commander->getAclEntry("user", $projPrincipal, { projectName => $ecscmProj });
    if ($xpath->findvalue('//principalName') eq $projPrincipal) {
        $batch->deleteAclEntry("user", $projPrincipal, { projectName => $ecscmProj });
    }
}

# Data that drives the create step picker registration for this plugin.
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Bazaar - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Bazaar - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Bazaar - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Bazaar - Preflight");

my %Checkout = (
                label       => "Bazaar - Checkout",
                procedure   => "CheckoutCode",
                description => "Checkout code from Bazaar.",
                category    => "Source Code Management"
               );

my %Preflight = (
                 label       => "Bazaar - Preflight",
                 procedure   => "Preflight",
                 description => "Checkout code from Bazaar during Preflight",
                 category    => "Source Code Management"
                );

@::createStepPickerSteps = (\%Checkout, \%Preflight);
