package PAUSE::Web::Controller::Admin::User;

use Mojo::Base "Mojolicious::Controller";
use PAUSE::Web::Util::Encode;
use Text::Soundex;
use Text::Metaphone;
use Text::Format;

sub add {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  if ($req->param("USERID")) {
    my $session = $c->new_session_counted;
    my $s = $session->{APPLY};
    for my $a (keys %$s) {
      $req->param("pause99_add_user_$a" => $s->{$a});
      warn "retrieving from session a[$a]s(a)[$s->{$a}]";
    }
  }

  my $userid;
  if ( $userid = $req->param("pause99_add_user_userid") ) {

    $userid = uc($userid);
    $userid ||= "";
    $pause->{userid} = $userid;

    my @error;
    if ( $userid !~ $mgr->config->valid_userid ) {
      push @error, {invalid => 1};
    }

    $req->param("pause99_add_user_userid" => $userid) if $userid;

    my $doit = 0;
    my $fullname_raw = $req->param('pause99_add_user_fullname') // '';
    my($fullname);
    $fullname = PAUSE::Web::Util::Encode::any2utf8($fullname_raw);
    warn "fullname[$fullname]fullname_raw[$fullname_raw]";
    if ($fullname ne $fullname_raw) {
      $req->param("pause99_add_user_fullname" => $fullname);
      my $debug = $req->param("pause99_add_user_fullname");
      warn "debug[$debug]fullname[$fullname]";
    }
    unless ($fullname) {
      warn "no fullname";
      push @error, {no_fullname => 1};
    }
    $pause->{fullname} = $fullname;

    unless (@error) {
      if ($req->param('SUBMIT_pause99_add_user_Definitely')) {
        $doit = 1;
      } elsif (
               $req->param('SUBMIT_pause99_add_user_Soundex')
               ||
               $req->param('SUBMIT_pause99_add_user_Metaphone')
              ) {

        # START OF SOUNDEX/METAPHONE check

        my ($surname);
        my($s_package) = $req->param('SUBMIT_pause99_add_user_Soundex') ?
            'Text::Soundex' : 'Text::Metaphone';

        ($surname = $fullname) =~ s/.*\s//;
        my $query = qq{SELECT userid, fullname, email, homepage,
                              introduced, changedby, changed
                       FROM   users
                       WHERE  isa_list=''
        };
        my $sth = $dbh->prepare($query);
        $sth->execute;
        my $s_func;
        if ($s_package eq "Text::Soundex") {
          $s_func = \&Text::Soundex::soundex;
        } elsif ($s_package eq "Text::Metaphone") {
          $s_func = \&Text::Metaphone::Metaphone;
        }
        my $s_code = $s_func->($surname);
        $pause->{s_package} = $s_package;
        $pause->{s_code} = $s_code;

        warn "s_code[$s_code]";
        my $requserid   = $req->param("pause99_add_user_userid")||"";
        my $reqfullname = $req->param("pause99_add_user_fullname")||"";
        my $reqemail    = $req->param("pause99_add_user_email")||"";
        my $reqhomepage = $req->param("pause99_add_user_homepage")||"";
        my($suserid,$sfullname, $spublic_email, $shomepage,
           $sintroduced, $schangedby, $schanged);
        # if a user has a preference to display secret emails in a
        # certain color, they can enter it here:
        my %se_color_map = (
                            jv => "black",
                            andk => "#f33",
                           );
        my $se_color = $se_color_map{lc $pause->{User}{userid}} || "red";
        $pause->{se_color} = $se_color;

        my @urows;
        while (($suserid, $sfullname, $spublic_email, $shomepage,
                $sintroduced, $schangedby, $schanged) =
               $mgr->fetchrow($sth, "fetchrow_array")) {
          (my $dbsurname = $sfullname) =~ s/.*\s//;
          next unless $s_func->($dbsurname) eq $s_code;
          my %urow;
          my $score = 0;
          my $ssecretemail = $c->get_secretemail($suserid);

          if (defined($suserid)&&length($suserid)) {
              if ($requserid eq $suserid) {
                  $urow{same_userid} = 1;
                  $score++;
              }
              $urow{userid} = $suserid;
          }
          {
              if ($sfullname eq $reqfullname) {
                  $urow{same_fullname} = 1;
                  $score++;
              } elsif ($sfullname =~ /\Q$surname\E/) {
                  $urow{surname} = $surname;
                  my ($before, $after) = split /\Q$surname\E/, $sfullname, 2;
                  $urow{before_surname} = $before // "";
                  $urow{after_surname} = $after // "";
                  $score++;
              }
              if (defined($sfullname)&&length($sfullname)) {
                  $urow{fullname} = $sfullname;
              }
          }
          my @email_parts = split '@', $spublic_email;
          {
              if ($spublic_email eq $reqemail) {
                  $urow{same_email} = 1;
                  $score++;
              }
              $urow{email_parts} = \@email_parts;
          }
          if ($ssecretemail) {
              $urow{secretemail} = $ssecretemail;

              if ($ssecretemail eq $reqemail) {
                  $urow{same_secretemail} = 1;
                  $score++;
              }
          }
          if ($shomepage) {
              if ($shomepage eq $reqhomepage) {
                  $urow{same_homepage} = 1;
                  $score++;
              }
              $urow{homepage} = $shomepage;
          }
          if ($sintroduced) {
            $urow{introduced} = scalar(gmtime($sintroduced));
          }
          if ($schanged) {
            $urow{changed} = scalar(gmtime($schanged));
          }
          $urow{changedby} = $schangedby;
          push @urows, {
            line => \%urow,
            score => $score,
          };
        }
        if (@urows) {
          $doit = 0;
          $pause->{urows} = \@urows;
        } else {
          $doit = 1;
        }

        # END OF SOUNDEX/METAPHONE check
      }
    }
    $pause->{doit} = $doit;

    if ($doit) {
      $c->add_user_doit($userid,$fullname);
    } elsif (@error) {
      $pause->{error} = \@error;
    } else {
      my $T = time;
      warn "T[$T]doit[$doit]userid[$userid]";
    }
  } else {
    warn "No userid, nothing done";
  }
}

sub get_secretemail {
  my ($c, $userid) = @_;
  my $mgr = $c->app->pause;
  my $dbh2 = $mgr->authen_connect;
  my $sth2 = $dbh2->prepare("SELECT secretemail
                             FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                             WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
  $sth2->execute($userid);
  my($h2) = $mgr->fetchrow($sth2, "fetchrow_array");
  $sth2->finish;
  $h2;
}

sub add_user_doit {
  my($c, $userid, $fullname) = @_;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $T = time;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  my($query,$sth,@qbind);
  my($email) = $req->param('pause99_add_user_email');
  my($homepage) = $req->param('pause99_add_user_homepage');
  my $subscribe = $req->param('pause99_add_user_subscribe') // '';
  my $entered_by = $pause->{User}{fullname} || $pause->{User}{userid};
  my $is_mailing_list = $subscribe gt '';
  if ( $is_mailing_list ) {
    $query = qq{INSERT INTO users (
                      userid,          isa_list,             introduced,
                      changed,         changedby)
                    VALUES (
                      ?,               ?,                    ?,
                      ?,               ?)};
    @qbind = ($userid,1,$T,$T,$pause->{User}{userid});
  } else {
    $query = qq{INSERT INTO users (
                            userid,     email,    homepage,  fullname,
                     isa_list, introduced, changed,  changedby)
                    VALUES (
                     ?,          ?,        ?,         ?,
                     ?,        ?,          ?,        ?)};
    @qbind = ($userid,"CENSORED",$homepage,$fullname,"",$T,$T,$pause->{User}{userid});
  }

  # We have a query for INSERT INTO users

  if ($dbh->do($query,undef,@qbind)) {
    $pause->{succeeded} = 1;

    if ( $is_mailing_list ) {
      # Add a mailinglist: INSERT INTO maillists

      my($maillistid) = $userid;
      my($maillistname) = $fullname;
      my($changed) = $T;
      $pause->{maillistname} = $maillistname;
      $pause->{subscribe} = $subscribe;

      $query = qq{INSERT INTO maillists (
                        maillistid, maillistname,
                        subscribe,  changed,  changedby,            address)
                      VALUES (
                        ?,          ?,
                        ?,          ?,        ?,                    ?)};
      my @qbind2 = ($maillistid,    $maillistname,
                    $subscribe,     $changed, $pause->{User}{userid}, $email);
      unless ($dbh->do($query,undef,@qbind2)) {
        die PAUSE::Web::Exception
            ->new(ERROR => [qq{Query[$query]with qbind2[@qbind2] failed. Reason:}, $DBI::errstr]);
      }

    } else {
      # Not a mailinglist: set and send one time password
      my $onetime = $c->set_onetime_password($userid, $email);
      $c->send_otp_email($userid, $email, $onetime);
      # send emails to user and modules@perl.org; latter must censor the
      # user's email address
      my ($subject, $blurb) = $c->send_welcome_email( [$email], $userid, $email, $fullname, $homepage, $entered_by );
      $c->send_welcome_email( $PAUSE::Config->{ADMINS}, $userid, "CENSORED", $fullname, $homepage, $entered_by );

      $pause->{subject} = $subject;
      $pause->{blurb}   = $blurb;
      $pause->{send_to} = join(" AND ", @{$PAUSE::Config->{ADMINS}}, $email);
    }

    warn "Info: clearing all fields";
    for my $field (qw(userid fullname email homepage subscribe)) {
      my $param = "pause99_add_user_$field";
      $req->param($param => "");
    }

  } else {
    $pause->{query} = $query;
    $pause->{query_error} = $dbh->errstr;
  }

  # usertable {
  {
    my $sql = "SELECT * FROM users WHERE userid=?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($userid);
    return unless $sth->rows == 1;
    my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");

    $pause->{usertable} = $rec;
  }
}

1;
