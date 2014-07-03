Percona Toolkit Plugin for Tungsten Replicator
==============================================

A while back, I made some changes on the plugin interface for ``pt-online-schema-change`` which allows custom replication checks to be written. 
As I was adding this functionality, I also added the ``--plugin`` option to ``pt-table-checksum``.
This was released in Percona Toolkit 2.2.8 (http://www.mysqlperformanceblog.com/2014/06/04/percona-toolkit-2-2-8-now-available/).

With these additions, I spent some time writing a plugin that allows the Percona Toolkit tools to use Tungsten Replicator to check for slave lag, you can find the code at https://github.com/grypyrg/percona-toolkit-plugin-tungsten-replicator

Requirements
------------

The plugin uses the perl JSON::XS module (``perl-JSON-XS`` rpm package, http://search.cpan.org/dist/JSON-XS/XS.pm), make sure it's available or the plugin will not work.


Preparation
-----------


We need to use the ``--recursion-method=dsns`` as the Percona Toolkit tools are not able to automatically find the tungsten replicator slaves that are connected to the master database. (I did add a blueprint on launchpad to make this possible https://blueprints.launchpad.net/percona-toolkit/+spec/plugin-custom-recursion-method)

The ``dsns`` recursion-method gets the list of slaves from a database table you specify::

	CREATE TABLE `percona`.`dsns` (
	  `id` int(11) NOT NULL AUTO_INCREMENT,
	  `parent_id` int(11) DEFAULT NULL,
	  `dsn` varchar(255) NOT NULL,
	  PRIMARY KEY (`id`)
	);

Here one slave ``node3`` is replicating from the master::

	node1 mysql> select * from percona.dsns;
	+----+-----------+---------+
	| id | parent_id | dsn     |
	+----+-----------+---------+
	|  2 |      NULL | h=node3 |
	+----+-----------+---------+


Configuration
-------------

Currently, it is not possible to specify extra options for the plugin with Percona Toolkit, so some manual editing of the perl file is still necessary to configure it.

So before we can run a checksum, we need to configure the plugin::

	## CONFIGURATION
	# trepctl command to run
	my $trepctl="/opt/tungsten/installs/cookbook/tungsten/tungsten-replicator/bin/trepctl";

	# what tungsten replicator service to check
	my $service="bravo";

	# what user does tungsten replicator use to perform the writes?
	# See Binlog Format for more information
	my $tungstenusername = 'tungsten';


Running A Checksum
------------------


Here I did a checksum of a table with ``pt-table-checksum``. During the checksum process, I brought the slave node offline and brought it back online again::

	# pt-table-checksum \
		-u checksum \
		--no-check-binlog-format \
		--recursion-method=dsn=D=percona,t=dsns \
		--plugin=/vagrant/pt-plugin-tungsten_replicator.pl  \
		--databases app \
		--check-interval=5 \
		--max-lag=10
	Created plugin from /vagrant/pt-plugin-tungsten_replicator.pl.
	PLUGIN get_slave_lag: Using Tungsten Replicator to check replication lag
	Tungsten Replicator status of host node3 is OFFLINE:NORMAL, waiting
	Tungsten Replicator status of host node3 is OFFLINE:NORMAL, waiting
	Replica node3 is stopped.  Waiting.
	Tungsten Replicator status of host node3 is OFFLINE:NORMAL, waiting

	Replica lag is 125 seconds on node3.  Waiting.
	Replica lag is 119 seconds on node3.  Waiting.
	Checksumming app.large_table:  22% 00:12 remain
	            TS ERRORS  DIFFS     ROWS  CHUNKS SKIPPED    TIME TABLE
	07-03T10:49:54      0      0  2097152       7       0 213.238 app.large_table


I recommend to change the check-interval higher than the default 1 second as running ``trepctl`` takes a while. This could slow down the process quite a lot.


Making Schema Changes
---------------------

The plugin also works with ``pt-online-schema-change``::

	# pt-online-schema-change \
		-u schemachange \
		--recursion-method=dsn=D=percona,t=dsns \
		--plugin=/vagrant/pt-plugin-tungsten_replicator.pl \
		--check-interval=5 \
		--max-lag=10 \
		--alter "add index (column1) " \
		--execute D=app,t=large_table 
	Created plugin from /vagrant/pt-plugin-tungsten_replicator.pl.
	Found 1 slaves:
	  node3
	Will check slave lag on:
	  node3
	PLUGIN get_slave_lag: Using Tungsten Replicator to check replication lag
	Operation, tries, wait:
	  copy_rows, 10, 0.25
	  create_triggers, 10, 1
	  drop_triggers, 10, 1
	  swap_tables, 10, 1
	  update_foreign_keys, 10, 1
	Altering `app`.`large_table`...
	Creating new table...
	Created new table app._large_table_new OK.
	Waiting forever for new table `app`.`_large_table_new` to replicate to node3...
	Altering new table...
	Altered `app`.`_large_table_new` OK.
	2014-07-03T13:02:33 Creating triggers...
	2014-07-03T13:02:33 Created triggers OK.
	2014-07-03T13:02:33 Copying approximately 8774670 rows...
	Copying `app`.`large_table`:  26% 01:21 remain
	Copying `app`.`large_table`:  50% 00:59 remain
	Replica lag is 12 seconds on node3.  Waiting.
	Replica lag is 12 seconds on node3.  Waiting.
	Copying `app`.`large_table`:  53% 02:22 remain
	Copying `app`.`large_table`:  82% 00:39 remain
	2014-07-03T13:06:06 Copied rows OK.
	2014-07-03T13:06:06 Swapping tables...
	2014-07-03T13:06:06 Swapped original and new tables OK.
	2014-07-03T13:06:06 Dropping old table...
	2014-07-03T13:06:06 Dropped old table `app`.`_large_table_old` OK.
	2014-07-03T13:06:06 Dropping triggers...
	2014-07-03T13:06:06 Dropped triggers OK.
	Successfully altered `app`.`large_table`.


As you can see, there was some slave lag during the schema changes.



Binlog Format & ``pt-online-schema-change``
-------------------------------------------

``pt-online-schema-change`` uses triggers in order to do the schema changes. Tungsten Replicator has some limitations with different binary log formats and triggers (https://code.google.com/p/tungsten-replicator/wiki/TRCAdministration#Triggers_and_Row_Replication).

In Tungsten Replicator, ``ROW`` based binlog events will be converted to SQL statements, which causes triggers to be executed on the slave as well, this does not happen with traditional replication.

Different settings:

- ``STATEMENT`` based binary logging works by default
- ``ROW`` based binary logging works, the plugin recreates the triggers and uses the technique documented at https://code.google.com/p/tungsten-replicator/wiki/TRCAdministration#Triggers_and_Row_Replication
- ``MIXED`` binary logging does not work, as there is currently no way to determine whether an event was written to the binary log in statement or row based format, so it's not possible to know if triggers should be run or not. The tool will exit and and error will be returned:: 

  	Error creating --plugin: The master it's binlog_format=MIXED, 
  	pt-online-schema change does not work well with 
  	Tungsten Replicator and binlog_format=MIXED.


Be Warned
"""""""""

The ``binlog_format`` can be overriden on a per session basis, make sure that this does NOT happen when using ``pt-online-schema-change``.


Summary
-------

The documentation on the Continuent website already mentions how you can compare data with ``pt-table-checksum`` (https://docs.continuent.com/tungsten-replicator-3.0/troubleshooting-datacompare.html).

I believe this plugin is a good addition to it. The features in Percona Toolkit that monitor replication lag can now be used with Tungsten Replicator  and therefore gives you control on how much replication lag is tolerated while using those tools.






