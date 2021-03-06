<?php
require 'vendor/autoload.php';
require_once 'config.inc.php';

use \actimeo\pgproc\PgProcedures;
use \actimeo\pgproc\PgProcException;

class groupTest extends PHPUnit_Framework_TestCase {
  private static $base;
  private static $pgHost;
  private static $pgUser;
  private static $pgPass;
  private static $pgPort;
  private static $pgDatabase;

  public static function setUpBeforeClass() {
    
    // Get connection params
    global $pg_host, $pg_user, $pg_pass, $pg_database, $pg_port;
    self::$pgHost = $pg_host;
    self::$pgUser = $pg_user;
    self::$pgPass = $pg_pass;
    self::$pgPort = $pg_port;
    self::$pgDatabase = $pg_database;
    self::assertNotNull(self::$pgHost);
    self::assertNotNull(self::$pgUser);
    self::assertNotNull(self::$pgPass);
    self::assertNotNull(self::$pgDatabase);
    
    // Create object
    self::$base = new PgProcedures (self::$pgHost, self::$pgUser, self::$pgPass, self::$pgDatabase,
				    self::$pgPort, '.traces');
    self::assertNotNull(self::$base);    
  }

  protected function assertPreConditions()
  {
    self::$base->startTransaction();
    $login = 'testdejfhcqcsdfkhn';
    $pwd = 'ksfdjgsfdyubg';    
    self::$base->execute_sql("INSERT INTO organ.participant (par_firstname, par_lastname) "
			     ."VALUES ('Test', 'User')");
    self::$base->execute_sql("insert into login.user (usr_login, usr_salt, usr_rights, par_id) values ('"
			     .$login."', pgcrypto.crypt('"
			     .$pwd."', pgcrypto.gen_salt('bf', 8)), '{organization}', "
			     ."(SELECT par_id FROM organ.participant WHERE par_firstname='Test'));");			  			  
    $res = self::$base->login->user_login($login, $pwd, null, null);
    $this->token = $res['usr_token'];
  }

  protected function assertPostConditions()
  {
    self::$base->rollback();
  }

  public function testGroupAdd() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);
    $this->assertGreaterThan(0, $orgId);

    $grp_name = 'a group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grp_name, $grp_desc, false, 'organization');
    $this->assertGreaterThan(0, $grpId);
  }  

  public function testGroupGet() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);
    $this->assertGreaterThan(0, $orgId);

    $grp_name = 'a group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grp_name, $grp_desc, false, 'organization');
    $this->assertGreaterThan(0, $grpId);

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals($grp_name, $grp['grp_name']);
  }  

  public function testGroupAddSameNameDifferentOrganization() {
    $name1 = 'organization 1';
    $desc1 = 'an organization 1 desc';
    $orgId1 = self::$base->organ->organization_add($this->token, $name1, $desc1, true);
    $name2 = 'organization 2';
    $desc2 = 'an organization 2 desc';
    $orgId2 = self::$base->organ->organization_add($this->token, $name2, $desc2, true);

    $this->assertGreaterThan(0, $orgId1);
    $this->assertGreaterThan(0, $orgId2);

    $grpName = 'a same group name';
    $grp_desc = 'a same group desc';
    $grpId1 = self::$base->organ->group_add($this->token, $orgId1, $grpName, $grp_desc, false, 'organization');
    $grpId2 = self::$base->organ->group_add($this->token, $orgId2, $grpName, $grp_desc, false, 'organization');
  }  

  /**
   * Add two groups with same name to the same organization
   * @expectedException \actimeo\pgproc\PgProcException
   */  
  public function testGroupAddSameNameSameOrganization() {
    $name = 'organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grpName = 'a same group';
    $grp_desc = 'a same group desc';
    $grpId1 = self::$base->organ->group_add($this->token, $orgId, $grpName, $grp_desc, false, 'organization');
    $grpId2 = self::$base->organ->group_add($this->token, $orgId, $grpName, $grp_desc, false, 'organization');
  } 

  public function testGroupSet() {
    $name = 'organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);
    
    $grpName = 'a group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grpName, $grp_desc, false, 'organization');
    $this->assertGreaterThan(0, $grpId);
    
    $grpNotes = 'a note';
    self::$base->organ->group_set($this->token, $grpId, $grpNotes);
    $grp = self::$base->organ->group_get($this->token, $grpId);
  }
  
  public function testGroupList() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'a group 1 desc';
    $grpId1 = self::$base->organ->group_add($this->token, $orgId, $grp_name1, $grp_desc1, false, 'organization');
    $this->assertGreaterThan(0, $grpId1);
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'a group 2 desc';
    $grpId2 = self::$base->organ->group_add($this->token, $orgId, $grp_name2, $grp_desc2, false, 'organization');
    $this->assertGreaterThan(0, $grpId2);
    
    $grps = self::$base->organ->group_list($this->token, $orgId, true);
    $this->assertEquals(2, count($grps));
  }
  
  public function testGroupDelete() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'a group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grp_name, $grp_desc, false, 'organization');

    $grps = self::$base->organ->group_list($this->token, $orgId, true);
    $this->assertEquals(1, count($grps));
    
    self::$base->organ->group_delete($this->token, $grpId);
    $grpsAfter = self::$base->organ->group_list($this->token, $orgId, true);
    $this->assertNull($grpsAfter);
  }

  public function testGroupRename() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'a group';
    $grp_desc = 'a group desc';
    $grp_name2 = 'another group';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grp_name1, $grp_desc, false, 'organization');
    self::$base->organ->group_rename($this->token, $grpId, $grp_name2);
    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals($grp_name2, $grp['grp_name']);
  }

  /**
   * Trying to rename an inexistant portal raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testGroupRenameUnknown() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'a group';
    $grp_desc = 'a group desc';
    $grp_name2 = 'another group';
    $grpId = self::$base->organ->group_add($this->token, $orgId, $grp_name1, $grp_desc, false, 'organization');
    self::$base->organ->group_rename($this->token, $grpId+1, $grp_name2);
  }

  /**
   * Trying to delete an inexistant portal raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testGroupDeleteUnknown() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'a service group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    self::$base->organ->group_delete($this->token, $grpId+1);
  }

  /**
   * Trying to delete a portal with null value as por_id raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testServiceDeleteNull() {
    self::$base->organ->group_delete($this->token, null);
  }

  public function testSetMandatoryFalseDefault() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'a service group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertFalse($grp['grp_mandatory']);
  }

  public function testSetMandatorySetTrue() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'a service group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    self::$base->organ->group_set_mandatory($this->token, $grpId, true);
    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertTrue($grp['grp_mandatory']);
  }

  public function testSetMandatorySetFalse() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'a service group';
    $grp_desc = 'a group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    self::$base->organ->group_set_mandatory($this->token, $grpId, true);
    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertTrue($grp['grp_mandatory']);

    self::$base->organ->group_set_mandatory($this->token, $grpId, false);
    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertFalse($grp['grp_mandatory']);
  }

  public function testGroupExclusiveNew() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $grp_name3 = 'group 3';
    $grp_desc3 = 'group desc 3';
    $grpId3 = self::$base->organ->group_add($this->token, $id, $grp_name3, $grp_desc3, false, 'organization');

    $grp_name4 = 'group 4';
    $grp_desc4 = 'group desc 4';
    $grpId4 = self::$base->organ->group_add($this->token, $id, $grp_name4, $grp_desc4, false, 'organization');

    self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', 
					    array($grpId1, $grpId2, $grpId3));
    $res = self::$base->organ->group_exclusive_with($this->token, $grpId1);
    $resIds = array_map(function($e) { return $e['grp_id']; }, $res);
    $this->assertEquals($resIds, array ($grpId1, $grpId2, $grpId3));
  }

  /**
   * Trying to add a group in two sets of exclusive groups should raise an exception
   */
  public function testGroupExclusiveNewGroupInSingleSet() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $grp_name3 = 'group 3';
    $grp_desc3 = 'group desc 3';
    $grpId3 = self::$base->organ->group_add($this->token, $id, $grp_name3, $grp_desc3, false, 'organization');

    $grp_name4 = 'group 4';
    $grp_desc4 = 'group desc 4';
    $grpId4 = self::$base->organ->group_add($this->token, $id, $grp_name4, $grp_desc4, false, 'organization');

    self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', array($grpId1, $grpId2, $grpId3));
    $this->setExpectedException('\actimeo\pgproc\PgProcException');
    self::$base->organ->group_exclusive_new($this->token, 'other exclusive groups', array($grpId1, $grpId4));
  }

  public function testGroupExclusiveWithNothing() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $grp_name3 = 'group 3';
    $grp_desc3 = 'group desc 3';
    $grpId3 = self::$base->organ->group_add($this->token, $id, $grp_name3, $grp_desc3, false, 'organization');

    $grp_name4 = 'group 4';
    $grp_desc4 = 'group desc 4';
    $grpId4 = self::$base->organ->group_add($this->token, $id, $grp_name4, $grp_desc4, false, 'organization');

    self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', 
					    array($grpId1, $grpId2, $grpId3));
    $res = self::$base->organ->group_exclusive_with($this->token, $grpId4);
    $this->assertNull($res);
  }

  public function testGroupExclusiveDelete() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $grp_name3 = 'group 3';
    $grp_desc3 = 'group desc 3';
    $grpId3 = self::$base->organ->group_add($this->token, $id, $grp_name3, $grp_desc3, false, 'organization');

    $grp_name4 = 'group 4';
    $grp_desc4 = 'group desc 4';
    $grpId4 = self::$base->organ->group_add($this->token, $id, $grp_name4, $grp_desc4, false, 'organization');

    $gre = self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', 
						   array($grpId1, $grpId2, $grpId3));
    $this->assertNotNull($gre);
    self::$base->organ->group_exclusive_delete($this->token, $grpId2);
    $res = self::$base->organ->group_exclusive_with($this->token, $grpId2);
    $this->assertNull($res);    
  }

  // create a set of exclusive groups with a mandtory group -> Exception
  public function testGroupExclusiveWhenMandatory() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    self::$base->organ->group_set_mandatory($this->token, $grpId1, true);
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $this->setExpectedException('\actimeo\pgproc\PgProcException');
    $gre = self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', 
						   array($grpId1, $grpId2));
  }

  // set a group mandatory when it is in an exclusive set -> Exception
  public function testGroupExclusiveMandatoryWhenExclusive() {
    $name = 'an organization';
    $desc = 'an organization desc';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name1 = 'group 1';
    $grp_desc1 = 'group desc 1';
    $grpId1 = self::$base->organ->group_add($this->token, $id, $grp_name1, $grp_desc1, false, 'organization');
    
    $grp_name2 = 'group 2';
    $grp_desc2 = 'group desc 2';
    $grpId2 = self::$base->organ->group_add($this->token, $id, $grp_name2, $grp_desc2, false, 'organization');
    
    $gre = self::$base->organ->group_exclusive_new($this->token, 'some exclusive groups', 
						   array($grpId1, $grpId2));

    $this->setExpectedException('\actimeo\pgproc\PgProcException');
    self::$base->organ->group_set_mandatory($this->token, $grpId1, true);
  }

  // Check if group_orientation default value is 'organization'
  public function testGroupSetOrientation() {
    $name = 'an organization';
    $desc = 'an organization description';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'group';
    $grp_desc = 'group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals('organization', $grp['grp_orientation']);
  }

  // set group_orientation value to 'participant'
  public function testGroupSetOrientationParticipant() {
    $name = 'an organization';
    $desc = 'an organization description';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'group';
    $grp_desc = 'group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    self::$base->organ->group_set_orientation($this->token, $grpId, 'participant');

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals('participant', $grp['grp_orientation']);
  }

  // set back group_orientation value to 'organization'
  public function testGroupSetOrentationOrganization() {
    $name = 'an organization';
    $desc = 'an organization description';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'group';
    $grp_desc = 'group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    self::$base->organ->group_set_orientation($this->token, $grpId, 'participant');

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals('participant', $grp['grp_orientation']);

    self::$base->organ->group_set_orientation($this->token, $grpId, 'organization');

    $grp = self::$base->organ->group_get($this->token, $grpId);
    $this->assertEquals('organization', $grp['grp_orientation']);
  }

  // get the list of group topics
  public function testGroupGetTopics() {
    $name = 'an organization';
    $desc = 'an organization description';
    $id = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'group';
    $grp_desc = 'group desc';
    $grpId = self::$base->organ->group_add($this->token, $id, $grp_name, $grp_desc, false, 'organization');

    $top_name = 'topic 1';
    $top_desc = 'topic description 1';
    $top_icon = 'topic icon 1';
    $top_color = 'topic color 1';
    $top_name2 = 'topic 2';
    $top_desc2 = 'topic description 2';
    $top_icon2 = 'topic icon 2';
    $top_color2 = 'topic color 2';
    $top_name3 = 'topic 3';
    $top_desc3 = 'topic description 3';
    $top_icon3 = 'topic icon 3';
    $top_color3 = 'topic color 3';
    $topId1 = self::$base->organ->topic_add($this->token, $top_name, $top_desc, $top_icon, $top_color);
    $topId2 = self::$base->organ->topic_add($this->token, $top_name2, $top_desc2, $top_icon2, $top_color2);
    $topId3 = self::$base->organ->topic_add($this->token, $top_name3, $top_desc3, $top_icon3, $top_color3);

    self::$base->organ->group_set_topics($this->token, $grpId, array($topId1, $topId2, $topId3));

    $topics = self::$base->organ->group_get_topics($this->token, $grpId);
    $this->assertEquals(3, count($topics));
  }

  public function testGroupUpdate() {
    $name = 'an organization';
    $desc = 'an organization description';
    $orgId = self::$base->organ->organization_add($this->token, $name, $desc, true);

    $grp_name = 'group';
    $grp_desc = 'group desc';
    $id = self::$base->organ->group_add($this->token, $orgId, $grp_name, $grp_desc, false, 'organization');

    $grp = self::$base->organ->group_get($this->token, $id);

    $this->assertEquals(array('grp_id'=>$id,'grp_name'=>$grp_name,'grp_description'=>$grp_desc,
			      'grp_mandatory'=>false,'grp_orientation'=>'organization','org_id'=>$orgId), $grp);

    $grpN = 'renamed group';
    $grpD = 'renamed description';
    self::$base->organ->group_update($this->token, $id, $grpN, $grpD, true, 'participant', $orgId);

    $grp = self::$base->organ->group_get($this->token, $id);

    $this->assertEquals(array('grp_id'=>$id,'grp_name'=>$grpN,'grp_description'=>$grpD,
			      'grp_mandatory'=>true,'grp_orientation'=>'participant','org_id'=>$orgId), $grp);

  }
}
