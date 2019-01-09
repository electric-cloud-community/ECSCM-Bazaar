# -------------------------------------------------------------------------
# Package
#    ECSCM::Bazaar::Driver
#
# Purpose
#    Object to represent interactions with Bazaar
# -------------------------------------------------------------------------
package ECSCM::Bazaar::Driver;
@ISA = (ECSCM::Base::Driver);

# -------------------------------------------------------------------------
# Includes
# -------------------------------------------------------------------------
use ElectricCommander;
use Getopt::Long;
use Cwd;
use File::Spec;
use File::Path;
use HTTP::Date(qw {str2time time2str time2iso time2isoz});

# -------------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------------
use constant {
	SUCCESS => 0,
	ERROR   => 1,	
};


if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::Bazaar::Cfg) {
    require ECSCM::Bazaar::Cfg;
}

####################################################################
# Object constructor for ECSCM::Bazaar::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#                 
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;
    my $sys;
    my $cfg = new ECSCM::Bazaar::Cfg($cmdr, $name);
    if ($name ne '') {
        $sys = $cfg->getSCMPluginName();
        if ("$sys" ne 'ECSCM-Bazaar') { die 'SCM config $name is not type ECSCM-Bazaar'; }
    }

    my ($self) = new ECSCM::Base::Driver($cmdr,$cfg);
    
    my $pluginKey = $sys;
    my $xpath = $cmdr->getPlugin($pluginKey);
    my $pluginName = $xpath->findvalue('//pluginVersion')->value;
    print "\nUsing plugin $pluginKey version $pluginName\n";

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode' || 
        $method eq 'apf_driver' || 
        $method eq 'cpf_driver') {
        return ERROR;
    } else {
        return SUCCESS;
    }
}

####################################################################
# helper utilties
####################################################################
#------------------------------------------------------------------------------
# bzr
#
#       run the supplied command.
#------------------------------------------------------------------------------
sub bzr
{
    my ($self,$command, $options) = @_;
    my $BazaarCommand = "bzr $command";        
    if ($options eq '') {
      $options = {LogCommand => 1, LogResult => 1}; 
    }
    my $out = $self->RunCommand($BazaarCommand, $options);           
    return $out;
}


####################################################################
# get scm tag for sentry (continuous integration)
####################################################################

####################################################################
# getSCMTag
# 
# Get the latest changelist on this branch/client
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
####################################################################
sub getSCMTag {       
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    } 
    
    # Load userName and password from the credential
    ($opts->{username}, $opts->{password}) = 
        $self->retrieveUserCredential($opts->{credential}, $opts->{username}, $opts->{password});
      
    my $username = $opts->{username};
    my $password = $opts->{password};
    my $branch = $self->setup_branch($opts->{branch}, $username, $password);
    my $tip = '-r-1';
    my $command = 'log';

    $command .= qq{ $branch $tip} unless $branch eq ''; 
    
    my ($using_http, $pStart, $pLength) = $self->pass_offset($command);
       
    #checkout the code    
    my $result = $self->bzr($command, {LogCommand => 1, LogResult => 1, HidePassword => $using_http,
                                        passwordStart => $pStart, 
                                        passwordLength => $pLength});  
    
    my $timestamp, $revno;
    foreach my $line (split (/\n/, $result)) {
              
        if ($line =~ /revno:\s(.*)/){
           $revno = $1;       
        }        
        if ($line =~ /timestamp: (.*)/) {
           $timestamp = $1;                     
           $timestamp =  $self->BZRstr2time($timestamp);                      
        }
    }        
    return ($revno, $timestamp);    
}

##########################################################################
#  BZRstr2time
#
#  Convert a date/time string in BZR format to standard
#  time representation.
#
#   Params:
#       timeStr - a string containing the time/date in CVS form
#
#   Returns:
#       t - integer number of seconds since epoch
#
##########################################################################
sub BZRstr2time($)
{
   my ($self, $timeStr) = @_;
      
    if (defined $timeStr) {
    #Thu 2011-06-16 15:51:08 -0600
    # Match on the parts we need: "2010-09-20 21:25:57"
    $timeStr =~ m/(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+) (.*)/i;
    
    $timeStr = "$1-$2-$3 $4:$5:$6 $7";
        
    # Convert to number of seconds since "epoch"
    my $t = str2time($timeStr);        
        return $t;
    } else {
      return ERROR;
    }
}

####################################################################
# checkoutCode
#
# Results:
#   Uses the "bzr checkout" command to checkout code to the workspace.
#   Collects data to call functions to set up the scm change log.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns
#   Output of the the "Bazaar sync" command
####################################################################
sub checkoutCode
{
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    }
    
    # Load userName and password from the credential
    ($opts->{username}, $opts->{password}) = 
        $self->retrieveUserCredential($opts->{credential}, $opts->{username}, $opts->{password});
        
    my $dest = $opts->{dest};
    my $username = $opts->{username};
    my $password = $opts->{password};
    my $branch_location = $self->setup_branch($opts->{branch_location}, $username, $password);
    my $lightweight = $opts->{lightweight};
    my $quiet = $opts->{quiet};
    my $revision = $opts->{revision};
    my $verbose = $opts->{verbose};       
    
    my $command = 'checkout';
       
    $command .= qq{ $branch_location} unless $branch_location eq '';    
    $command .= qq{ "$dest"} unless $dest eq '';
    $command .= qq{ -r $revision} unless $revision eq '';
    $command .= qq{ --quiet} unless $quiet eq 'false';
    $command .= qq{ --verbose} unless $verbose eq 'false';    
    $command .= qq{ --lightweight} unless $lightweight eq 'false';
    
    my ($using_http, $pStart, $pLength) = $self->pass_offset($command);
       
    #checkout the code    
    my $result = $self->bzr($command, {LogCommand => 1, LogResult => 1, HidePassword => $using_http,
                                        passwordStart => $pStart, 
                                        passwordLength => $pLength});  
    
    #changelog    
    my $scmKey = "Bazaar-$name";

    my $start = '';

    if ($opts->{lastSnapshot} && $opts->{lastSnapshot} ne '') {
          # use the lastSnapshot that was passed in.
          # note: don't include
          # the change given by $::gLastSnapshot, since that was already
          # included in the previous build.
          $opts->{lastSnapshot}++;
          $start = $opts->{lastSnapshot};
    } else {
          $start = $self->getStartForChangeLog($scmKey);
    }

    if ($start eq '') {
        if ($revision eq '') {         
          my $tip = '-r-1';
          $command = 'log';
          $command .= qq{ $branch_location $tip} unless $branch_location eq '';    
          my $result = $self->bzr($command, {LogCommand => 0, LogResult => 0});
          
          foreach my $line (split (/\n/, $result)) {              
              if ($line =~ /revno:\s(.*)/){
                $revision = $1;       
              }    
           }               
        } else {
            $start = $revision;
        }        
    }
    
    $command = 'log';    
    $command .= qq{ $branch_location} unless $branch_location eq '';        
    $command .= qq{ -r $revision} unless $revision eq '';   

    my $changes = $self->bzr($command,
                    {LogCommand => 0});

    $self->setPropertiesOnJob($scmKey, $revision, $changes);
        
    return $result;     
}

#------------------------------------------------------------------------------
# setup_branch
#
#       Take the branch_location param and determines if it needs to embed the user
# and password according to the parameter and the specified protocol.
# if the parameter is not a url, the routine won't change the string. 
#------------------------------------------------------------------------------
sub setup_branch {
  my ($self, $branch_location, $user, $pass) = @_;
          
    #check for ssh+bzr
    if ($branch_location =~ m/(bzr\+ssh:\/\/)/) {
        #if doesn't have the user name
        if ($branch_location !~ m/(.+)@(.+)/i) {
           $self->issueWarningMsg ("Warning: *** You 've specified a password, you can't"  
                                 . " use a password with bzr+ssh protocol, the parameter has been ignored.")
                                 unless length $pass eq 0;
                                      
           substr $branch_location, length ('bzr+ssh://'), 0, "$user@";
        }          
    } else {    
    
        #if the name doesnt contain the user name and password
        if ($branch_location !~ m/(.+):(.+)@(.+)/i) {  
            my $user_pass = "$user:$pass@";
            
            #http or https    
            if ($branch_location =~ m/https:/i) {      
                substr $branch_location, length ('https://'), 0, $user_pass;          
            }elsif ($branch_location =~ m/http:/i) {
                substr $branch_location, length ('http://'), 0, $user_pass; 
            }       
        } else { #it's a local path
           $branch_location = "\"$branch_location\"";
        }
    }    
    return $branch_location;
}

#------------------------------------------------------------------------------
# pass_offset
#
#    If the command contains http determines the offset of the password   
#    return the if the client is using http, the password start and the length
#------------------------------------------------------------------------------
sub pass_offset {
    my ($self, $cmd) = @_;
    my $passwordStart;  
    my $passwordLength;
    my $using_http;
    
    if ($cmd =~ m/http/i) {    
           
        $TARGET = 2; #match the second occurence 
        $count = 0;

        while ($cmd =~ m/:/g) { if (++$count == $TARGET) { $passwordStart =  pos($cmd); } }      
        
        my $passwordEnd;
        if ($cmd =~ m/@/g) { $passwordEnd = pos($cmd);  }
        
        #this is because the run command adds the base command
        $passwordStart += length("bzr ");
        $passwordEnd += length("bzr ");
        
        $passwordLength = ($passwordEnd - $passwordStart) -1; 
        $using_http = 1;  
    } else { 
      $passwordStart = -1;
      $passwordLength = -1;    
      $using_http = 0;        
    }
    
    return $using_http, $passwordStart, $passwordLength;
}

#----------------------------------------------------------
# agent preflight functions
#----------------------------------------------------------

#------------------------------------------------------------------------------
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#------------------------------------------------------------------------------

sub apf_getScmInfo
{
    my ($self,$opts) = @_;
    my $scmInfo = $self->pf_readFile('ecpreflight_data/scmInfo');
    $scmInfo =~ m/(.*)\n(.*)/;
    $opts->{scm_workdir} = $1;
    $opts->{branch_location} = $2;
    print("Bazaar information received from client:\n"
            . "BazaarWorkdir: $opts->{scm_workdir}\n"
            . "BranchLocation: $opts->{branch_location}\n");
}

#------------------------------------------------------------------------------
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------

sub apf_createSnapshot
{
    my ($self,$opts) = @_;

    my $jobId = $::ENV{COMMANDER_JOBID};
    
    my $result = $self->checkoutCode($opts);
    if (defined $result) {
        print "checked out $result\n";
    }
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub apf_driver()
{  
    my ($self,$opts) = @_;    
    
    if ($opts->{test}) { $self->setTestMode(1); }
    
    $opts->{delta} = 'ecpreflight_files';

    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);
    $self->apf_deleteFiles($opts);
    $self->apf_overlayDeltas($opts);
}


####################################################################
# client preflight file
####################################################################


#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds all new and modified files, and calls putFiles to upload them
#       to the server.
#------------------------------------------------------------------------------
sub cpf_copyDeltas() {
    my ($self, $opts) = @_;
    $self->cpf_display('Collecting delta information');
      
    # change to the bazaar dir
    if (!defined($opts->{scm_workdir}) ||  "$opts->{scm_workdir}" eq '') {
        $self->cpf_error("Could not change to directory $opts->{scm_workdir}");
    }   
    
    chdir ($opts->{scm_workdir}) || $self->cpf_error("Could not change to directory $opts->{scm_workdir}");    
    $self->cpf_saveScmInfo($opts,"$opts->{scm_workdir}\n$opts->{scm_branch}"); 
    
    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    
    my $files = ();
    if ($opts->{scm_method} ne 'remote') {
        # get files that are different between the working directory
        # and the local repostitory
        $files = $self->cpf_localDelta($opts);
    } else {
        $files = $self->cpf_remoteDelta($opts);
    }
    
    my $top = getcwd();

    foreach my $f ( @{ $files->{deltafile} } ) {
        my $fpath = $top . "/$f";
        my $fpath = File::Spec->rel2abs($fpath);
        $self->cpf_addDelta($opts,$fpath, "$f");
    }
    foreach my $d ( @{ $files->{delfiles} } ) {
        $self->cpf_addDelete("$d");           
    }
     
    $self->cpf_closeManifestFiles($opts);
    $self->cpf_uploadFiles($opts);    
}

#------------------------------------------------------------------------------
# cpf_localDelta
#
#   use bzr status to find deltas between working dir and local repo
#   retrieves both tracked and untracked files
#
#  returns the files in a list   
#------------------------------------------------------------------------------
sub cpf_localDelta {
    my ($self, $opts) = @_;
    $self->cpf_display('Collecting deltas from local repo');
    
    my $output  = $self->RunCommand( "bzr status -S -r-1", {LogCommand => 1, IgnoreError=>1});
    $self->cpf_debug("$output");
            
    my $files =();    
    foreach(split(/\n/, $output)) {
        my $line = $_;         
        #file and action matchers        
        
        if ($line =~ m/(\+N|M|\?)\s+(.*)/) {
            $action = $1;
            $file = $2;                   
            
            if (($action eq '+N') || ($action eq 'M') || ($action eq '?') ) {  
                push @ { $files->{deltafile} } , $file;
            }
                
            if (($action eq 'D')) {                          
               push @ { $files->{delfiles} } , $file;
            }            
        }            
    }
    return $files;    
}

#------------------------------------------------------------------------------
# cpf_remoteDelta
#
#       use bzr diff to find deltas between local repo and remote repo
# Returns an array with the list of files
#------------------------------------------------------------------------------
sub cpf_remoteDelta
{
    my ($self, $opts) = @_;
    $self->cpf_display('Collecting deltas between local and remote');


    my $deltas  = $self->RunCommand( "bzr diff -r \"$opts->{scm_branch}\"",
          {LogCommand => 1, IgnoreError=>1});
          

    # Parse the output 

    #=== added file 'New Text Document.txt'
    #=== modified file 'test2.txt'
    #--- test2.txt   2011-06-17 17:13:19 +0000
    #+++ test2.txt   2011-06-30 23:01:00 +0000
    #@@ -0,0 +1,1 @@
    #+fff
    #\ No newline at end of file
    #
    #=== removed file 'test4.txt'
   
    my $files = ();   
    foreach(split(/\n/, $deltas)) {
        my $line = $_;
        if ($line =~ m/^===\smodified\sfile\s\'(.*)\'/) {
            # modified files
            push @ { $files->{deltafile} } , $1;
            $self->cpf_debug("modified file $1");
        }
        if ($line =~ m/^===\sadded\sfile\s\'(.*)\'/) {
            # added files
            push @ { $files->{deltafile} } , $1;
            $self->cpf_debug("added file $1");
        }
        if ($line =~ m/^===\sremoved\sfile\s\'(.*)\'/) {
            # deleted files
            push @ { $files->{delfiles} } , $1;
            $self->cpf_debug("deleted file $1");
        }
    }
    return $files;
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self, $opts) = @_;

    $self->cpf_display('Committing changes');
    $self->RunCommand("Bazaar commit -m '$opts->{scm_commitComment}'", {LogCommand =>1});
   
    $self->cpf_display('Changes have been successfully submitted');
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver
{
    my ($self,$opts) = @_;
    $self->cpf_display('Executing Bazaar actions for ecpreflight');

    $::gHelpMessage .= "
    Bazaar Options: 
    --workdir   <path>      The developer's source directory.
    --branch    <name>      The branch name for the preflight.
    --method= local get tracked and untracked changes in the current workingdir | remote get changes between working tree and remote branch";
  

    my %ScmOptions = (         
        "workdir=s"             => \$opts->{scm_workdir}, 
        "method=s"              => \$opts->{scm_method},
		"branch=s"              => \$opts->{scm_branch},
    );

    Getopt::Long::Configure('default');
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }    

    if ($::gHelp eq '1') {
        $self->cpf_display($::gHelpMessage);
        return;
    }    

    $self->extractOption($opts,'scm_workdir', { required => 1, cltOption => 'workdir' });  
    $self->extractOption($opts,'scm_branch', { required => 1, cltOption => 'branch' });  
	
    # Copy the deltas to a specific location.
    $self->cpf_copyDeltas($opts);

    # Auto commit if the user has chosen to do so.

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

#-------------------------------------------------------------------
# updateLastGoodAndLastCompleted
#
# Side Effects:
#   If the current job outcome is "success" copy the current
#   revision from the job level property to the "lastGood"
#   property and the "lastCompleted" property.  If not success,
#   only copy the current revision to the "lastCompleted" property.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns:
#   nothing.
#
#-------------------------------------------------------------------
sub updateLastGoodAndLastCompleted
{
    my ($self, $opts) = @_;

    my $prop = "/myJob/outcome";

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, 'getProperty', $prop);

    if ($success) {

    my $grandParentStepId = '';
    $grandParentStepId = $self->getGrandParentStepId();
    
    if (!$grandParentStepId || $grandParentStepId eq '') {
        # log that we couldn't get the grand parent step id
        return;
    }

    my $properties = $self->getPropertyNamesAndValuesFromPropertySheet("/myJob/ecscm_snapshots");

    foreach my $key ( keys % {$properties}) {
        my $snapshot = $properties->{$key}; 
        
        if ($snapshot ne '') { 
    
        $prop = "/myProcedure/ecscm_snapshots/$key/lastCompleted";
        $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, 'setProperty', $prop, $snapshot, {jobStepId => $grandParentStepId});

        my $val = '';
        $val = $xpath->findvalue('//value')->value();

    if ($val eq 'success') {
            $prop = "/myProcedure/ecscm_snapshots/$key/lastGood";
            $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, 'setProperty', $prop, $snapshot, {jobStepId => $grandParentStepId});            
        }

        } else {
        # log that we couldn't get the job revision
        }
    }

    } else {
    # log the error code and msg
    }
}
1;
