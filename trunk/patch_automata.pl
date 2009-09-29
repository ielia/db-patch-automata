#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use IPC::Open2;

# Configuration [start] -------------------------------------------------------
my $DEBUG=0;
my $DIR=`dirname "$0"`;
chomp($DIR);
my $DBVARIABLES_FILE="$DIR/dbvariables.sh";
my $PATCHES_LIST_FILENAME="$DIR/patches.list";
my $SELECT_EXECUTED_PATCHES=
	'SELECT patch FROM environmentpatch WHERE status = 2';
# Configuration [ end ] -------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Get environment variables from dbvariables file.
# Parameters: NONE.
# Returns:
#   - Patch Manager host name,
#   - Patch Manager port number,
#   - Patch Manager database name,
#   - Patch Manager user name and
#   - Patch Manager password.
sub get_env {
  my ($cmd,$out);

  open2($out,$cmd,'/bin/bash') || die "Could NOT execute $DBVARIABLES_FILE.";
  print $cmd ". '$DBVARIABLES_FILE';\n";
  print $cmd "echo \"\${PG_PATCHMANAGER_DB_HOST}\"\n";
  my $host=<$out>; chomp $host;
  print $cmd "echo \"\${PG_PATCHMANAGER_DB_PORT}\"\n";
  my $port=<$out>; chomp $port;
  print $cmd "echo \"\${PG_PATCHMANAGER_DB}\"\n";
  my $db=<$out>; chomp $db;
  print $cmd "echo \"\${PG_PATCHMANAGER_DB_USER}\"\n";
  my $user=<$out>; chomp $user;
  print $cmd "echo \"\${PG_PATCHMANAGER_DB_PASS}\"\n";
  my $pass=<$out>; chomp $pass;
  close($cmd);
  close($out);

  return ($host,$port,$db,$user,$pass);
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Connect to a PostgreSQL database.
# Parameters:
#   - Host name ($host)
#   - Port number ($port)
#   - Database name ($db)
#   - User name ($user)
#   - Password ($pass)
# Returns: DBI database handler.
sub db_connect {
  my ($host,$port,$db,$user,$pass)=@_;

  my $db_datasource="DBI:Pg:dbname=$db;host=$host;port=$port";
  print "Connecting to $db_datasource ($user).\n" if($DEBUG);
  my $dbh=DBI->connect_cached($db_datasource,$user,$pass);
  print STDERR "DB ERROR: $DBI::errstr\n" if(!defined $dbh);

  return $dbh;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Disconnect from a database.
# Parameters:
#   - DBI database handler ($dbh).
# Returns: NOTHING.
sub db_disconnect {
  my $dbh=shift;
  $dbh->disconnect;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Gets the list of executed patches (the ones that completed their
#              execution).
# Parameters:
#   - DBI database handler ($dbh).
# Returns:
#   - Error value (0 if no errors occurred, non-zero otherwise), and
#   - Hashmap with the patch names as keys and amount of times as values.
sub get_executed_patches_hashmap {
  my $dbh=shift;
  my %hash=();
  my $get_executed_patches_sth=$dbh->prepare("$SELECT_EXECUTED_PATCHES");
  if(!defined $get_executed_patches_sth){
    print STDERR "DB ERROR: Could NOT prepare 'get_executed_patches' ",
    	"statement\n";
    return -1;
  }
  my $rv=$get_executed_patches_sth->execute();
  if(!defined $rv or !$rv){
    print STDERR "DB ERROR: ",$get_executed_patches_sth->errstr,"\n";
    return -1;
  }
  while(my @row=$get_executed_patches_sth->fetchrow_array){
    ++$hash{$row[0]};
  }
  $get_executed_patches_sth->finish();
  return 0, %hash;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Prints out the list of patches that were run and are not in the
#              patches.list file (or that the number of times is higher).
# Parameters:
#   - Executed patches hashmap [patch -> amount of times] (%executed_pathes).
# Returns: NOTHING.
sub print_extra_patches {
  my %executed_patches=@_;

  print "Patches been run that are not in the list:\n";
  my $i=0;
  for my $patch (sort keys %executed_patches){
    my $times_ran=$executed_patches{$patch};
    if($times_ran){
      ++$i;
      print "$patch";
      if($executed_patches{$patch}>1){
        print "\t(ran $executed_patches{$patch} more times)";
      }
      print "\n";
    }
  }
  print "NONE\n" if($i==0);
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Parse the patches.list file and get the contents into a hashmap.
# Parameters:
#   - Patches hashmap pointer ($patches)
# Returns:
#   - Error value (0 if no errors occurred, non-zero otherwise).
sub read_patches_file {
  my $patches=shift;

  my ($err,$i)=(0,0);

  my $PATCHES_LIST;
  print "Opening file '$PATCHES_LIST_FILENAME'\n" if($DEBUG);
  my $rv=open($PATCHES_LIST,$PATCHES_LIST_FILENAME);
  if(!$rv){
    print STDERR "ERROR: Could NOT open file '$PATCHES_LIST_FILENAME'.\n",
    	"Aborting...\n";
    return -1;
  }
  while(<$PATCHES_LIST>){
    ++$i;
    chomp;
    if(/^\s*$/){
      print "($i) Blank line\n" if($DEBUG);
    }elsif(/^\s*#/){
      print "($i) Comment: $_\n" if($DEBUG);
    }elsif(/^\s*(@(([^\\@]*|\\\\*@|\\*[^@])*)@)?\s*([^@\s]+)\s*(@(([^\\@]*|\\\\*@|\\*[^@])*)@)?\s*(#(.*))?$/){
      my $pre_misc=$2;
      my $patch=$4;
      my $post_misc=$6;
      my $patch_comment=$9;
      $pre_misc=unescape_string($pre_misc);
      $post_misc=unescape_string($post_misc);
      $patch_comment=unescape_string($patch_comment);
      push @$patches,{pre=>$pre_misc,patch=>$patch,post=>$post_misc,
      	comment=>$patch_comment};
      print "($i) Pre: '$pre_misc' - Patch: '$patch' - Post: '$post_misc' - ",
      	"Comment: '$patch_comment'\n" if($DEBUG);
    }else{
      print STDERR "Malformed line $i\n";
      ++$err;
    }
  }
  close($PATCHES_LIST);
  print "File read successfully\n" if($DEBUG);

  if($err){
    print STDERR "ERROR: Malformed patches file.\nAborting...\n";
    return -1;
  }

  return 0;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
sub run_patch {
  my ($patch,$executed_patches)=@_;

  if(exists $executed_patches->{$patch->{'patch'}} and
  	$executed_patches->{$patch->{'patch'}}>0){
    # Patch was run
    --$executed_patches->{$patch->{'patch'}};
    print "Patch $patch->{patch} already run.\n" if($DEBUG);
  }else{
    # Patch wasn't run (as many times as the file specifies)
    # Show patch
    print "Patch: '",$patch->{'patch'},"'\n";
    # Show comment
    print "  Comment: ",$patch->{'comment'},"\n";
    # Check patch precondition
    if($patch->{'pre'} ne ""){
      print "  Patch precondition: ",$patch->{'pre'},
      	"\n  Fulfilled? (yes/no): ";
      my $answer=lc(<STDIN>);
      chomp($answer);
      while($answer ne 'yes' and $answer ne 'no'){
        print "  Fulfilled? (yes/no): ";
        $answer=lc(<STDIN>);
        chomp($answer);
      }
      if($answer eq 'no'){
        print "There are still patches to be run.\n",
        	"Please retry after fulfulling the dependencies.\n",
        	"Will carry on from this patch.\n";
        return -1;
      }
    }
    # Run patch
    my $rv=system("./patch_runner.sh $patch->{'patch'} 2>&1");
    if($rv){
      print STDERR "Could NOT run patch '$patch->{patch}'.\n",
      	"Aborting...\n";
      return -1;
    }
    # Check patch postcondition
    if($patch->{'post'} ne ""){
      print "  Patch postcondition: ",$patch->{'post'},
      	"\n  Fulfilled? (yes/no): ";
      my $answer=lc(<STDIN>);
      chomp($answer);
      while($answer ne 'yes' and $answer ne 'no'){
        print "  Fulfilled? (yes/no): ";
        $answer=lc(<STDIN>);
        chomp($answer);
      }
      if($answer eq 'no'){
        print "There may still be patches to be run.\n",
        	"Please retry after fulfulling the dependencies.\n",
        	"Will carry on from the next patch.\n";
        return -1;
      }
    }
  }

  return 0;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Take out the escaping backslashes from a string.
# Parameters:
#   - String ($str)
# Returns:
#   - Unescaped string.
sub unescape_string {
  my $str=shift;

  if(defined $str){
    $str=~s/(^|[^\\])(\\\\)*\\@/$1$2@/g;
    $str=~s/(^|[^\\])(\\\\)*\\n/$1$2\n/g;
    $str=~s/\\\\/\\/g;
  }else{
    $str='';
  }

  return $str;
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Description: Main procedure.
sub main {
  my ($err,$i,$patch,$post_misc,$pre_misc,$ret,$rv)=(0,0,'','','','',0);
  my @patches=();
  my %executed_patches=();

  # Get environment variables
  my ($PG_PATCHMANAGER_DB_HOST,$PG_PATCHMANAGER_DB_PORT,$PG_PATCHMANAGER_DB,
  	$PG_PATCHMANAGER_DB_USER,$PG_PATCHMANAGER_DB_PASS)=get_env();

  # Get a database connection
  my $dbh=db_connect($PG_PATCHMANAGER_DB_HOST,$PG_PATCHMANAGER_DB_PORT,
  	$PG_PATCHMANAGER_DB,$PG_PATCHMANAGER_DB_USER,$PG_PATCHMANAGER_DB_PASS);
  return -1 if(!defined $dbh);

  # Get executed patches from the database
  ($rv, %executed_patches)=get_executed_patches_hashmap($dbh);
  if($rv){
    db_disconnect($dbh);
    return -1;
  }

  # Disconnect from the database, because no longer required
  db_disconnect($dbh);

  # Read the patches list file
  return -1 if(read_patches_file(\@patches));

  # Process patches one by one
  for my $patch (@patches){
    return -1 if(run_patch($patch,\%executed_patches));
  }

  # Show the patches that have been run and are not in the list
  print_extra_patches(%executed_patches);

  return 0;
}
#------------------------------------------------------------------------------

exit main();
