#!/usr/bin/perl -w

#######################################################################
#
#	This script makes Data Cube entries to the Magic Table (MT)
#	for all variables of WBM daily output using MT entry for ID_runoff_d.
#
#	Written by Dr. A. Prusevich (alex.proussevitch@unh.edu)
#
#	December, 2013
#	Modifiled-	April, 2016
#
#######################################################################


use strict;
use Getopt::Long;
use File::Basename;
use PDL::NetCDF;
use Fcntl;
use Time::JulianDay;
use Time::DaysInMonth;
use RIMS;		### WSAG UNH module

#######################################################################
#############   Process and check command line inputs   ###############

my ($help, $list) = (0, 0);
						# Get command line optionsa
usage() if !GetOptions('h'=>\$help, 'dc'=> \$list) or $help;

my $runoffID = shift() or usage();

#######################################################################
			### Other Initializations

my $param_file	= '/net/nfs/ipswich/raid/atlas/data/WBM_dataCube_expand.csv';

my $names_file	= get_file_path()->{names_file};
my @keys	= read_attrib_keys($names_file);
my %names	= read_attrib($names_file, $runoffID, 'Code_Name');
   $names{Code_Name} =~ s/(_\w)$//;
my $mnth	= $1 eq '_d' ? 0 : 1;
   $names{Polygon_Aggregation} = 'riverbasinmask_207 statemask';	#### CHANGE IF NEEDED
#    $names{Polygon_Aggregation} = 'riverbasinmask_207 country_6min';	#### CHANGE IF NEEDED
check_MT_date($names{Start_Date});
check_MT_date($names{End_Date});

		### Find first file for WBM output
my ($j_date_list,$date_list) = make_date_list($names{Start_Date},$names{End_Date},\%names);
my $file	= (make_file_list($j_date_list,\%names,1e10,'0_0'))->[0][0];

		### Data Cube components
my @suff	= qw/_d _m _y _dc _mc _yc/;
my @ts		= qw/daily monthly yearly daily_clim monthly_clim yearly_clim/;
my @ts_full	=('daily','monthly','yearly','daily climatology','monthly climatology','yearly climatology');
my $ts_org	= $mnth ? 'monthly' : 'daily';
my @s_date	= dc_dates($names{Start_Date},0);
my @e_date	= dc_dates($names{End_Date},  1);
my @bands	= (0,12,1,365,12,1);
my @path	= dc_path($names{File_Path},$mnth);
my %par		= read_hashes($param_file);	### Read hashes for WBM output variables

#######################################################################
#############   Expand WBM output variables to a Data Cube   ##########

foreach my $var  (get_var_list($file,\%par)) {
 (my $data_cube = $names{Code_Name}) =~ s/runoff/$var/;
		### Process Data Cube codes only
  if ($list) {
    print "\t'$data_cube',\n";
    next;
  }
		### Process Magic Table entries
  for (my $i=0; $i<6; $i++ ) {
    next if $mnth && ($i==0 || $i==3);	### monthly WBM data

    my %meta = %names;
    $meta{Code_Name}	= $data_cube.$suff[$i];
    $meta{Data_Cube}	= $data_cube;
    $meta{Time_Series}	= $ts[$i];
    $meta{Start_Date}	= $s_date[$i];
    $meta{End_Date}	= $e_date[$i];
    $meta{Name}		=~s/Runoff/$par{$var}{Full_name}/i;
    $meta{Name}		=~s/$ts_org/$ts_full[$i]/i;
    $meta{Var_Name}	= $var;
    $meta{Param_Name}	= $par{$var}{Par_name};
    $meta{Round}	= $par{$var}{Round};
    $meta{Shade_Default}= $par{$var}{Shading};
    $meta{Legend_File}	= $par{$var}{Legend}	[$i % 3];
    $meta{Units}	= $par{$var}{Units}	[$i % 3];
    $meta{Orig_Units}	= $par{$var}{Org_units}	[$i % 3];
    $meta{Var_Scale}	= $par{$var}{Scale}	[$i % 3];
    $meta{Bands}	= $bands[$i] if $i;
   ($meta{File_Path}	= $path[$i]) =~ s/_VAR_/$var/;

		### Print attributes to STDOUT
    print join("\t",map($meta{$_},@keys)),"\n";
# map print("$_ = $meta{$_}\n"),@keys;
# die "\n\n";
  }
}

exit;

#######################################################################
######################  Functions  ####################################

sub read_hashes
{
  my ($hdr, @data) = read_table(shift);
  my %hash;
		### Populate parameter hash for the variables
  my $vCol = delete $$hdr{Var};
  foreach my $row (@data) {
    $hash{$$row[$vCol]} = {map(($_ => $$row[$$hdr{$_}]), keys(%$hdr))};
  }
		### Evaluate arrays
  foreach my $var (keys %hash) {
    foreach my $key (keys %{$hash{$var}}) {
      $hash{$var}{$key} = eval($hash{$var}{$key}) if $hash{$var}{$key} =~ m/\[.+]/;
    }
  }

  return %hash;
}

#######################################################################

sub dc_dates
{
  my($dt,$dr) = @_;

  my @date  = split m/-/, $dt;
  my @dir   = $dr ? (-1,12,31) : (1,1,1);

  my @dates = (	sprintf("%04d-%02d-%02d",@date[0..2]), sprintf("%04d-%02d-00",@date[0,1]), sprintf("%04d-00-00",$date[0]),
		sprintf("0000-%02d-%02d",@dir [1..2]), sprintf("0000-%02d-00",$dir[1]),    "0000-00-00");
			### Case of partial year
  $dates[2] =	sprintf("%04d-00-00",$date[0]+$dir[0]) if $date[1] != $dir[1];

  return @dates;
}

#######################################################################

sub dc_path
{
  my @path = ((shift) x 6);
  my $mnth = shift;
  my $p = $1 if $path[0] =~ m/(.+\/)/;
     $p =~ s/(daily|monthly)\/$//;

#   $path[1] = $p.($mnth?'':'monthly/_VAR_/').'wbm__YEAR_.nc;';
  $path[1] = $p.'monthly/_VAR_/wbm__YEAR_.nc;' unless $mnth;
  $path[2] = $p.'yearly/_VAR_/wbm__YEAR_.nc;';
  $path[3] = $p.'climatology/wbm__VAR__dc.nc;';
  $path[4] = $p.'climatology/wbm__VAR__mc.nc;';
  $path[5] = $p.'climatology/wbm__VAR__yc.nc;';

  return @path;
}

#######################################################################

sub get_var_list
{
  my ($file,$r)	= @_;
      $file	=~ s/.+:(.+):.+/$1/;		### Strip NetCDF extras
  my (@varlist, @varList);
		### Get variables
  my $ncobj = PDL::NetCDF->new ($file, {MODE => O_RDONLY});
  map {push(@varlist,$_) unless m/time|lat|lon/} @{$ncobj->getvariablenames()};
		### Check existance of the variable hashes
  foreach my $var (@varlist) {
    next if $var=~m/dischMsk/ && !exists($$r{$var});
    die "\tProblem: Variable \"$var\" is not found in the WBM variable table...\n".
	"\tPlease, add it to-\n\t$param_file\n" unless exists $$r{$var};

    push @varList, $var;
  }
		### Sort variables
  @varList = sort {$$r{$a}{Rank} <=> $$r{$b}{Rank}} @varList;

  return @varList;
}

#######################################################################

sub read_attrib_keys
{
  my $file = shift;

  open (FILE, "<$file") or die "Couldn't open $file, $!";
    my $line      = <FILE>;
       $line      =~ s/\r//;      ### Windows second end of the line char
    chomp $line;
    my $sep       = $line =~ m/\t/ ? "\t" : ',';
    my $re        = qr/(?:^|$sep)(?:"([^"]*)"|([^$sep]*))/;
    my @field     = split_csv_line($line,$re);
  close FILE;

  return @field;
}

sub split_csv_line
{
  my ($line,$re) = @_;
  my @cells;

  while($line =~ /$re/g) {
    my $value = defined $1 ? $1 : $2;
    push @cells, (defined $value ? $value : '');
  }
  return @cells;
}

#######################################################################

sub usage

{
  my $app_name = basename($0);
  print <<EOF;

Usage:
	$app_name [-h] [-dc] WBM_RUNOFF_ID

This code generates datacube entries to the Magic Table for WBM output variables.

Options:

h	Display this help.
dc	Generate Data Cube list to be used with "data_cube.pl".

EOF
  exit;
}

#######################################################################
