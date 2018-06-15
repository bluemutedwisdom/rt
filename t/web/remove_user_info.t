use strict;
use warnings;

use RT::Test tests => undef;

RT::Config->Set( 'ShredderStoragePath', RT::Test->temp_directory . '' );

my ( $baseurl, $agent ) = RT::Test->started_ok;

diag("Test server running at $baseurl");
my $url = $agent->rt_base_url;

# Login
$agent->login( 'root' => 'password' );

# Anonymize User
{
    my $root = RT::Test->load_or_create_user( Name => 'root' );
    ok $root && $root->id;

    my $user_id = $root->id;

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $user_id );
    $agent->follow_link_ok( { text => 'Anonymize' } );

    $agent->submit_form_ok( { form_id => 'user-info-modal', },
        "Anonymize user" );

    is $root->ValidateEmail('root@example.com'), 1, 'User Email removed';

# UserId is still the same, but all other records should be anonimyzed for TestUser
    my ( $ret, $msg ) = $root->Load($user_id);
    ok $ret;

    is $root->Name =~ /anon_/, 1, 'Username replaced with anon name';

    my @user_idenifying_info = qw (
        Address1 Address2 City Comments Country EmailAddress
        FreeformContactInfo Gecos HomePhone MobilePhone NickName Organization
        PagerPhone RealName Signature SMIMECertificate State Timezone WorkPhone Zip
        );

    # Ensure that all other user fields are blank
    foreach my $attr (@user_idenifying_info) {
        is $root->$attr, '', 'Attribute ' . $attr . ' is blank';
    }

    # Test that customfield values are removed with anonymize user action
    my $customfield = RT::CustomField->new( RT->SystemUser );
    ( $ret, $msg ) = $customfield->Create(
        Name       => 'TestCustomfield',
        LookupType => 'RT::User',
        Type       => 'FreeformSingle',
    );
    ok $ret, $msg;

    ( $ret, $msg ) = $customfield->AddToObject($root);
    ok( $ret, "Added CF to user object - " . $msg );

    ( $ret, $msg ) = $root->AddCustomFieldValue(
        Field => 'TestCustomfield',
        Value => 'Testing'
    );
    ok $ret, $msg;

    is $root->FirstCustomFieldValue('TestCustomfield'), 'Testing',
        'Customfield exists and has value for user.';

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $root->id );
    $agent->follow_link_ok( { text => 'Anonymize' } );

    $agent->submit_form_ok(
        {   form_id => 'user-info-modal',
            fields  => { clear_customfields => 'On' },
        },
        "Anonymize user and customfields"
    );

    is $root->FirstCustomFieldValue('TestCustomfield'), undef,
        'Customfield value cleared';
}

# Test replace user
{
    my $root = RT::Test->load_or_create_user(
        Name       => 'root',
        Password   => 'password',
        Privileged => 1
    );
    ok $root && $root->id;

    ok( RT::Test->set_rights(
            { Principal => $root, Right => [qw(SuperUser)] },
        ),
        'set rights'
      );

    ok $agent->logout;
    ok $agent->login( 'root' => 'password' );

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $root->id );
    $agent->follow_link_ok( { text => 'Replace' } );

    $agent->submit_form_ok(
        {   form_id => 'shredder-search-form',
            fields  => { WipeoutObject => 'User:name' . $root->Name, },
            button  => 'Wipeout'
        },
        "Replace user"
    );

    is $root->ValidateName( $root->Name ), 1,
        'User successfully deleted with replace';
}

# Test Remove user
{
    my $root = RT::Test->load_or_create_user(
        Name       => 'root',
        Password   => 'password',
        Privileged => 1
    );
    ok $root && $root->id;

    ok( RT::Test->set_rights(
            { Principal => $root, Right => [qw(SuperUser)] },
        ),
        'set rights'
      );

    $agent->logout;
    $agent->login( 'root' => 'password' );

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $root->id );
    $agent->follow_link_ok( { text => 'Remove' } );

    $agent->submit_form_ok(
        {   form_id => 'shredder-search-form',
            fields  => { WipeoutObject => 'User:name-' . $root->Name, },
            button  => 'Wipeout'
        },
        "Remove user"
    );

    is $root->ValidateName( $root->Name ), 1,
        'User successfully deleted with remove';
}

done_testing();
