<?php
/*
** portal
 - add 
 - rename
 - delete
 - clean 
 - list

 ** mainsection
 - add
 - remove
 - reorder
 - unique order
*/
require 'vendor/autoload.php';
require_once 'config.inc.php';

use \actimeo\pgproc\PgProcedures;
use \actimeo\pgproc\PgProcException;

class portalTest extends PHPUnit_Framework_TestCase {
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
			     .$pwd."', pgcrypto.gen_salt('bf', 8)), '{structure}', "
			     ."(SELECT par_id FROM organ.participant WHERE par_firstname='Test'));");			  			     
    $res = self::$base->login->user_login($login, $pwd, null, null);
    $this->token = $res['usr_token'];
  }

  protected function assertPostConditions()
  {
    self::$base->rollback();
  }

  public function testPortalAdd() {
    $name = 'a portal';
    $desc = 'a desc';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
    $this->assertGreaterThan(0, $id);
  }  

  /**
   * Add two portals with same name
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPortalAddSameName() {
    $name = 'a portal';
    $desc = 'a desc';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
    $this->assertGreaterThan(0, $id);
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
  }  

  public function testPortalList() {
    $name = 'a portal';
    $desc = 'a desc';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
    $portals = self::$base->portal->portal_list($this->token);
    $this->assertGreaterThan(0, count($portals));
    $found = false;
    foreach ($portals as $portal) {
      if ($name == $portal['por_name']) {
	$found = true;
	break;
      }
    }
    $this->assertTrue($found);
  }

  public function testPortalGet() {
    $name = 'a portal';
    $desc = 'a portal description';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);

    $por = self::$base->portal->portal_get($this->token, $id);

    $this->assertEquals('a portal', $por['por_name']);
    $this->assertEquals('a portal description', $por['por_description']);
  }

  public function testPortalRename() {
    $name1 = 'a portal';
    $name2 = 'another portal';
    $desc1 = 'a desc';
    $id = self::$base->portal->portal_add($this->token, $name1, $desc1);
    self::$base->portal->portal_rename($this->token, $id, $name2, $desc1);
    $portals = self::$base->portal->portal_list($this->token);
    $this->assertGreaterThan(0, count($portals));
    $portal = $portals[0];
    $found = false;
    foreach ($portals as $portal) {
      if ($name2 == $portal['por_name']) {
	$found = true;
	break;
      }
    }
    $this->assertTrue($found);
  }

  /**
   * Trying to rename an inexistant portal raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPortalRenameUnknown() {
    $name1 = 'a portal';
    $name2 = 'another portal';
    $desc = 'a desc';
    $id = self::$base->portal->portal_add($this->token, $name1, $desc);
    self::$base->portal->portal_rename($this->token, $id+1, $name2, $desc);
  }

  public function testPortalDelete() {
    $name1 = 'a portal';
    $desc1 = 'a desc';
    $id1 = self::$base->portal->portal_add($this->token, $name1, $desc1);
    $name2 = 'another portal';
    $desc2 = 'another desc';
    $id2 = self::$base->portal->portal_add($this->token, $name2, $desc2);
    $portals = self::$base->portal->portal_list($this->token);
    $nAfterAdd = count($portals);
    $this->assertGreaterThan(0, count($portals));   
    self::$base->portal->portal_delete($this->token, $id1);
    $portals = self::$base->portal->portal_list($this->token);
    $this->assertEquals($nAfterAdd-1, count($portals));
  }

  /**
   * Trying to delete an inexistant portal raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPortalDeleteUnknown() {
    $name = 'a portal';
    $desc = 'another desc';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
    self::$base->portal->portal_delete($this->token, $id+1);
  }

  /**
   * Trying to delete a portal with null value as por_id raises an exception
   * @expectedException \actimeo\pgproc\PgProcException
   */
  public function testPortalDeleteNull() {
    $name = 'a portal';
    $desc = 'another desc';
    $id = self::$base->portal->portal_add($this->token, $name, $desc);
    self::$base->portal->portal_delete($this->token, null);
  }

  public function testPortalClean() {
    $por_name = 'a portal';
    $por_desc = 'another desc';
    $por_id = self::$base->portal->portal_add($this->token, $por_name, $por_desc);
    
    $mse_name1 = 'a first section';
    $mse_name2 = 'a second section';
    $pse_name1 = 'a first section';
    $pse_name2 = 'a second section';
    $id1 = self::$base->portal->mainsection_add($this->token, $por_id, $mse_name1);
    $id2 = self::$base->portal->mainsection_add($this->token, $por_id, $mse_name2);
    self::$base->portal->personsection_add($this->token, $por_id, $pse_name1);
    self::$base->portal->personsection_add($this->token, $por_id, $pse_name2);
    self::$base->portal->portal_clean($this->token, $por_id);
    $this->setExpectedException('\actimeo\pgproc\PgProcException');
    self::$base->portal->portal_rename($this->token, $por_id, 'new name', 'new desc');
  }

}
