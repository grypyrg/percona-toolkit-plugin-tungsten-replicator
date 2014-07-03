## CONFIGURATION
# trepctl command to run
my $trepctl="/opt/tungsten/installs/cookbook/tungsten/tungsten-replicator/bin/trepctl";

# what tungsten replicator service to report on
my $service="alpha";


# ###############################################################
# The actual get_slave_lag which is invoked by the plugin classes
# ###############################################################
{
package plugin_tungsten_replicator;

use Data::Dumper;
local $Data::Dumper::Indent    = 1;
local $Data::Dumper::Sortkeys  = 1;
local $Data::Dumper::Quotekeys = 0;

use JSON::XS;

sub get_slave_lag {
   my ($self, %args) = @_;
   # oktorun is a reference, also update it using $$oktorun=0;
   my $oktorun=$args{oktorun};
   
   print "PLUGIN get_slave_lag: Using Tungsten Replicator to check replication lag\n";

   my $get_lag = sub {
         my ($cxn) = @_;

         my $hostname = $cxn->{hostname};
         my $lag;
         my $json = `$trepctl -host $hostname -service $service status -json`;

         # if trepctl doesn't return 0, something went wrong and we should abort 
         # the complete process
         my $return = $? >> 8;
         if ( $return != 0 )
         {
            $$oktorun=0;
            die "\nCould not run trepctl successfully for $hostname in order to get replication lag:\n"
               . $json;

         }

         my $status = decode_json $json;


         if ( $status->{state} ne "ONLINE" ) {
            print "Tungsten Replicator status of host $hostname is " . $status->{state} . ", waiting\n";
            return;
         }


         $lag = sprintf("%.0f", $status->{appliedLatency});

         # we return oktorun and the lag
         return $lag;
   };

   return $get_lag;
}
}
1;
# #############################################################################
# pt_online_schema_change_plugin
# #############################################################################
{
package pt_online_schema_change_plugin;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub get_slave_lag {
   return plugin_tungsten_replicator::get_slave_lag(@_);
}
}
1;

# #############################################################################
# pt_table_checksum_plugin
# #############################################################################
{
package pt_table_checksum_plugin;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub get_slave_lag {
   return plugin_tungsten_replicator::get_slave_lag(@_);
}
}
1;