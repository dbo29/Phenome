
=head1

load_solcap_TA_phenotypes.pl

=head1 SYNOPSIS

    $ThisScript.pl -H [dbhost] -D [dbname] [-t] -i infile 

=head1 COMMAND-LINE OPTIONS

 -H  host name 
 -D  database name 
 -i infile 
 -t  Test run . Rolling back at the end.


=head2 DESCRIPTION

This is a script for loading solcap phenotypes, as scored by using Tomato Analyzer software -post harvest 

See the solCap template for the 'TA_color', 'Longitudinal' and Latitudinal' spreadsheet for  more details 



=head2 AUTHOR

Naama Menda (nm249@cornell.edu)

August 2010
 
=cut


#!/usr/bin/perl
use strict;
use Getopt::Std; 
use CXGN::Tools::File::Spreadsheet;

use Bio::Chado::Schema;
use CXGN::DB::InsertDBH;
use Date::Calc qw(
		  Delta_Days
		  check_date
		  );
use Carp qw /croak/ ;



our ($opt_H, $opt_D, $opt_i, $opt_t);

getopts('H:i:tD:');

my $dbhost = $opt_H;
my $dbname = $opt_D;
my $file = $opt_i;

my $dbh = CXGN::DB::InsertDBH->new( { dbhost=>$dbhost,
				      dbname=>$dbname,
				      dbargs => {AutoCommit => 0,
						 RaiseError => 1}
				    }
    );

my $schema= Bio::Chado::Schema->connect(  sub { $dbh->get_actual_dbh() } ,  { on_connect_do => ['SET search_path TO  public;'] } );


#getting the last database ids for resetting at the end in case of rolling back
###############
my $last_nd_experiment_id = $schema->resultset('NaturalDiversity::NdExperiment')->get_column('nd_experiment_id')->max;
my $last_cvterm_id = $schema->resultset('Cv::Cvterm')->get_column('cvterm_id')->max;

my $last_nd_experiment_project_id = $schema->resultset('NaturalDiversity::NdExperimentProject')->get_column('nd_experiment_project_id')->max;
my $last_nd_experiment_stock_id = $schema->resultset('NaturalDiversity::NdExperimentStock')->get_column('nd_experiment_stock_id')->max;
my $last_nd_experiment_phenotype_id = $schema->resultset('NaturalDiversity::NdExperimentPhenotype')->get_column('nd_experiment_phenotype_id')->max;
my $last_phenotype_id = $schema->resultset('Phenotype::Phenotype')->get_column('phenotype_id')->max;

my %seq  = (
    'nd_experiment_nd_experiment_id_seq' => $last_nd_experiment_id,
    'cvterm_cvterm_id_seq' => $last_cvterm_id,
    'nd_experiment_project_nd_experiment_project_id_seq' => $last_nd_experiment_project_id,
    'nd_experiment_stock_nd_experiment_stock_id_seq' => $last_nd_experiment_stock_id,
    'nd_experiment_phenotype_nd_experiment_phenotype_id_seq' => $last_nd_experiment_phenotype_id,
    'phenotype_phenotype_id_seq' => $last_phenotype_id, 
    );

# get the project 
my $project_name = 'solcap vintage tomatoes 2009, Fremont, OH';
my $project = $schema->resultset("Project::Project")->find( {
    name => $project_name,
} );
# get the geolocation 
my $geo_description = 'OSU-OARDC Fremont, OH';
my $geolocation = $schema->resultset("NaturalDiversity::NdGeolocation")->find( {
    description => $geo_description ,
} );

# find the cvterm for a phenotyping experiment
my $pheno_cvterm = $schema->resultset('Cv::Cvterm')->create_with(
                         { name   => 'phenotyping experiment',
                           cv     => 'experiment type',
                           db     => 'null',
                           dbxref => 'phenotyping experiment',
                         });


#new spreadsheet, skip 3 first columns
my $spreadsheet=CXGN::Tools::File::Spreadsheet->new($file, 3);
    
my $sp_person_id = undef; # who is the owner ? SolCap was loaded for the project. 

my @rows = $spreadsheet->row_labels();
my @columns = $spreadsheet->column_labels();

eval {
	
    foreach my $plot (@rows ) { 
	#$plot number is the row label. Need to get the matching stock 
	#plot is a stock, with a relationship 'is_plot_of' of a parent accession
	# the sct number is a stockprop of that accession.
	
	my ($parent_stock) = $schema->resultset("Stock::Stockprop")->find( {
	    value => $sct} )->search_related('stock');
	
	my $plot = $spreadsheet->value_at($sct, "Plot Number");
	my $rep = $spreadsheet->value_at($sct, "Replicate Number");
	my $comment = $spreadsheet->value_at($sct, "Comment");
	
	#get these 2 params from the user, or from the database based on project input.
	my $year = '2009';
	my $location = "Fremont, OH";
	##########################################
	# find the child stock based on plot name 
	my $stock = $parent_stock->search_related('stock_relationship_subjects')->search_related('subject', { name=> $plot ,  uniquename => $plot ."_" . $rep . "_" . $year.",". $location  });
	
	my $fruit_number =  $spreadsheet->value_at($sct, $fruit_number);

	
      COLUMN: foreach my $label (@columns) { 
	  my $value =  $spreadsheet->value_at($sct, $label);
	  
	  my ($db_name, $sp_accession) = split (/\:/ , $label);
	  next() if (!$sp_accession);
	  next() if !$value;
	  
	  my ($sp_term) = $schema->resultset("General::Db")->find( {
	      name => $db_name } )->find_related("dbxrefs", { 
		  accession=>$sp_accession , } )->search_related("cvterm");
	  
	  
	  my ($pato_term) = $schema->resultset("General::Db")->find( {
	      name => 'PATO' , } )->search_related
		  ("dbxrefs")->search_related
		  ("cvterm_dbxrefs", {
		      cvterm_id => $sp_term->cvterm_id() , 
		  });
	  my $pato_id = undef;
	  $pato_id = $pato_term->cvterm_id() if $pato_term;
	  
	  #store the phenotype
	  my $phenotype = $sp_term->find_or_create_related("phenotype_observables", { 
	      attr_id => $sp_term->cvterm_id(),
	      value => $value ,
	      cvalue_id => $pato_id,
	      uniquename => "$project_name, Fruit number: $fruit_number, plot: $plot, Term: " . $sp_term->name() ,
	  });
	  
	  
	  #check if the phenotype is already associated with an experiment
	  # which means this loading script has been run before .
	  if ( $phenotype->find_related("nd_experiment_phenotypes", {} ) ) {
	      warn "This experiment has been stored before! Skipping! \n";
	      next();
	  }
	  print STDOUT "db_name = '$db_name' sp_accession = '$sp_accession'\n";
	  print "Value $value \n";
	  print "Stored phenotype " . $phenotype->phenotype_id() . " with attr " . $sp_term->name . " value = $value, cvalue = PATO " . $pato_id . "\n\n";
	  ########################################################
	  ###store a new nd_experiment. Each phenotype is going to get a new experiment_id
	  my $experiment = $schema->resultset('NaturalDiversity::NdExperiment')->create( {
	      nd_geolocation_id => $geolocation->nd_geolocation_id(),
	      type_id => $pheno_cvterm->cvterm_id(),
	  } );
	  
	  #link to the project
	  $experiment->find_or_create_related('nd_experiment_projects', {
	      project_id => $project->project_id()
	      } );
	  
	  #link to the stock
	  $experiment->find_or_create_related('nd_experiment_stocks' , {
	      stock_id => $stock->stock_id(),
	      type_id  =>  $pheno_cvterm->cvterm_id(),
	  });
	  
	  
	  # link the phenotype with the experiment
	  my $nd_experiment_phenotype = $experiment->find_or_create_related('nd_experiment_phenotype', { phenotype_id => $phenotype->phenotype_id() } );
	  
	  
	  # store the unit for the measurement (if exists) in phenotype_cvterm
	  #$phenotype->find_or_create_related("phenotype_cvterms" , {
	  #	cvterm_id => $unit_cvterm->cvterm_id() } ) if $unit_cvterm;
	  #print "Loaded phenotype_cvterm with cvterm '" . $unit_cvterm->name() . " '\n" if $unit_cvterm ; 
      }
    }
};



if ($@) { print "An error occured! Rolling backl!\n\n $@ \n\n "; }
elsif ($opt_t) {
    print "TEST RUN. Rolling back and reseting database sequences!!\n\n";
    foreach my $value ( keys %seq ) { 
	my $maxval= $seq{$value} || 0;
	if ($maxval) { $dbh->do("SELECT setval ('$value', $maxval, true)") ;  }
	else {  $dbh->do("SELECT setval ('$value', 1, false)");  }
    }
    $dbh->rollback;

}else {
    print "Transaction succeeded! Commiting phenotyping experiments! \n\n";
    $dbh->commit();
}
