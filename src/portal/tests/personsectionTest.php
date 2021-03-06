<?php
require 'vendor/autoload.php';
require_once 'config.inc.php';

use \actimeo\pgproc\PgProcedures;
use \actimeo\pgproc\PgProcException;

class personSectionTest extends PHPUnit_Framework_TestCase {
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
			     .$pwd."', pgcrypto.gen_salt('bf', 8)),  '{structure}', "
			     ."(SELECT par_id FROM organ.participant WHERE par_firstname='Test'));");			  			 
    $res = self::$base->login->user_login($login, $pwd, null, null);
    $this->token = $res['usr_token'];
  }

  protected function assertPostConditions()
  {
    self::$base->rollback();
  }

  public function testPersonsectionAdd() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);

    $pse_name = 'a main section';
    $id = self::$base->portal->personsection_add($this->token, $por_id, $pse_name);
    $this->assertGreaterThan(0, $id);
  }

  public function testPersonsectionAddTwice() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name1 = 'a first section';
    $pse_name2 = 'a second section';
    $id1 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name1);
    $id2 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name2);
    $this->assertGreaterThan($id1, $id2);
  }

  /**
   * Add two personsections with same name in same portal
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPersonsectionAddSameName() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name = 'a first section';
    $id1 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name);
    $id2 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name);
  }  

  /**
   * Add two personsections with same name in different portals
   */
  public function testPersonsectionAddSameNameOtherPortal() {
    $por_name1 = 'a first portal';
    $por_desc1 = 'a portal desc';
    $por_id1 = self::$base->portal->portal_add($this->token, $por_name1, $por_desc1);
    $por_name2 = 'a second portal';
    $por_desc2 = 'a portal desc';
    $por_id2 = self::$base->portal->portal_add($this->token, $por_name2, $por_desc2);
    
    $pse_name = 'a section';
    $id1 = self::$base->portal->personsection_add($this->token, $por_id1, $pse_name);
    $id2 = self::$base->portal->personsection_add($this->token, $por_id2, $pse_name);
    $this->assertGreaterThan($id1, $id2);
  }  

  public function testPersonsectionAddAndList() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);

    $pse_name = 'a main section';
    $id = self::$base->portal->personsection_add($this->token, $por_id, $pse_name);
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(1, count($personsections));
  }

  public function testPersonsectionAddTwiceAndList() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name1 = 'a first section';
    $pse_name2 = 'a second section';
    $id1 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name1);
    $id2 = self::$base->portal->personsection_add($this->token, $por_id, $pse_name2);
    
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(2, count($personsections));    
  }

  public function testPersonsectionAddDifferentPortalsAndList() {
    $por_name1 = 'a first portal';
    $por_desc1 = 'a portal desc';
    $por_id1 = self::$base->portal->portal_add($this->token, $por_name1, $por_desc1);
    $por_name2 = 'a second portal';
    $por_desc2 = 'a portal desc';
    $por_id2 = self::$base->portal->portal_add($this->token, $por_name2, $por_desc2);
    
    $pse_name = 'a section';
    $id1 = self::$base->portal->personsection_add($this->token, $por_id1, $pse_name);
    $id2 = self::$base->portal->personsection_add($this->token, $por_id2, $pse_name);

    $personsections = self::$base->portal->personsection_list($this->token, $por_id1);
    $this->assertEquals(1, count($personsections));

    $personsections = self::$base->portal->personsection_list($this->token, $por_id2);
    $this->assertEquals(1, count($personsections));
  }

  public function testPersonsectionAddAndCheckOrder() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name[0] = 'a first section';
    $pse_name[1] = 'a second section';
    $pse_name[2] = 'a third section';
    $pse_name[3] = 'a fourth section';
    for ($i=0; $i<4; $i++)
      $id[$i] = self::$base->portal->personsection_add($this->token, $por_id, $pse_name[$i]);
    
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(4, count($personsections));
    for ($i=0; $i<4; $i++) {
      $this->assertEquals($i+1, $personsections[$i]['pse_order']);
      $this->assertEquals($pse_name[$i], $personsections[$i]['pse_name']);
    }
  }

  public function testPersonsectionRename() {
    $name1 = 'a section';
    $name2 = 'another section';
    $por_desc = 'a portal desc';
    $por = self::$base->portal->portal_add($this->token, 'a portal', $por_desc);
    
    $id = self::$base->portal->personsection_add($this->token, $por, $name1);
    self::$base->portal->personsection_rename($this->token, $id, $name2);
    $personsections = self::$base->portal->personsection_list($this->token, $por);
    $this->assertEquals(1, count($personsections));
    $personsection = $personsections[0];
    $this->assertEquals($name2, $personsection['pse_name']);
    
  }

 /**
   * Trying to rename an inexistant personsection raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
   public function testPersonsectionRenameUnknown() {
    $name1 = 'a section';
    $name2 = 'another section';
    $por_desc = 'a portal desc';
    $por = self::$base->portal->portal_add($this->token, 'a portal', $por_desc);
    
    $id = self::$base->portal->personsection_add($this->token, $por, $name1);
    self::$base->portal->personsection_rename($this->token, $id+1, $name2);
  }

  public function testPersonsectionDelete() {
    $por = self::$base->portal->portal_add($this->token, 'a portal', 'a desc');
    $id = self::$base->portal->personsection_add($this->token, $por, 'a section');
    $personsections = self::$base->portal->personsection_list($this->token, $por);
    $this->assertEquals(1, count($personsections));
    self::$base->portal->personsection_delete($this->token, $id);
    $personsections = self::$base->portal->personsection_list($this->token, $por);
    $this->assertNull($personsections);
  }

  /**
   * Trying to delete an inexistant portal raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPersonsectionDeleteUnknown() {
    $name = 'a portal';
    $desc = 'a portal desc';
    $por = self::$base->portal->portal_add($this->token, $name, $desc);
    $id = self::$base->portal->personsection_add($this->token, $por, 'a section');
    self::$base->portal->personsection_delete($this->token, $id+1);
  }

  public function testPersonsectionAddAndMoveToMiddle() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name[0] = '1';
    $pse_name[1] = '2';
    $pse_name[2] = '3';
    $pse_name[3] = '4';
    for ($i=0; $i<4; $i++)
      $id[$i] = self::$base->portal->personsection_add($this->token, $por_id, $pse_name[$i]);
    
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(4, count($personsections));

    self::$base->portal->personsection_move_before_position($this->token, $id[2], 1);
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(array('3', '1', '2', '4'), $this->getPseNames($personsections));
  }

  public function testPersonsectionAddAndMoveToStart() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name[0] = '1';
    $pse_name[1] = '2';
    $pse_name[2] = '3';
    $pse_name[3] = '4';
    for ($i=0; $i<4; $i++)
      $id[$i] = self::$base->portal->personsection_add($this->token, $por_id, $pse_name[$i]);
    
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(4, count($personsections));

    self::$base->portal->personsection_move_before_position($this->token, $id[3], 1);
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(array('4', '1', '2', '3'), $this->getPseNames($personsections));
  }

  public function testPersonsectionAddAndMoveToEnd() {
    $por_name = 'a portal';
    $por_desc = 'a portal desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $pse_name[0] = '1';
    $pse_name[1] = '2';
    $pse_name[2] = '3';
    $pse_name[3] = '4';
    for ($i=0; $i<4; $i++)
      $id[$i] = self::$base->portal->personsection_add($this->token, $por_id, $pse_name[$i]);
    
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(4, count($personsections));

    self::$base->portal->personsection_move_before_position($this->token, $id[0], 5);
    $personsections = self::$base->portal->personsection_list($this->token, $por_id);
    $this->assertEquals(array('2', '3', '4', '1'), $this->getPseNames($personsections));
  }
  
  private function getPseNames($a) {
    $ret = array();
    foreach($a as $v) {
      $ret[] = $v['pse_name'];
    }
    return $ret;
  }

}
