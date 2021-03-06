CREATE OR REPLACE FUNCTION notes.note_add(
  prm_token integer, 
  prm_text text,
  prm_event_date timestamp with time zone,
  prm_object text,
  prm_topics integer[], 
  prm_dossiers integer[],
  prm_recipients_info integer[],
  prm_recipients_action integer[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  new_id integer;
  author_id integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  SELECT par_id INTO author_id FROM login.user WHERE usr_token = prm_token;
  INSERT INTO notes.note (not_text, not_creation_date, not_event_date, not_object, not_author)
    VALUES (prm_text, CURRENT_TIMESTAMP, prm_event_date, prm_object, author_id)
    RETURNING not_id INTO new_id;

  PERFORM notes.note_set_topics(prm_token, new_id, prm_topics);
  PERFORM notes.note_set_dossiers(prm_token, new_id, prm_dossiers);
  PERFORM notes.note_set_recipients(prm_token, new_id, false, (SELECT array_agg(ids) FROM unnest(prm_recipients_info) ids WHERE ids <> all(prm_recipients_action)));
  PERFORM notes.note_set_recipients(prm_token, new_id, true, prm_recipients_action);
  RETURN new_id;
END;
$$;
COMMENT ON FUNCTION notes.note_add(
  prm_token integer,
  prm_text text,
  prm_event_date timestamp with time zone,
  prm_object text,
  prm_topics integer[], 
  prm_dossiers integer[],
  prm_recipients_info integer[],
  prm_recipients_action integer[])
 IS 'Add a new note';

CREATE OR REPLACE FUNCTION notes.note_update(prm_token integer, prm_not_id integer, prm_recipients_info integer[], prm_recipients_action integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM notes.note WHERE not_id = prm_not_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM notes.note_set_recipients(prm_token, prm_not_id, false, prm_recipients_info);
  PERFORM notes.note_set_recipients(prm_token, prm_not_id, true, prm_recipients_action);
END;
$$;
COMMENT ON FUNCTION notes.note_update(prm_token integer, prm_not_id integer, prm_recipients_info integer[], prm_recipients_action integer[]) IS 'Update a note';

CREATE OR REPLACE FUNCTION notes.note_set_topics(
  prm_token integer,
  prm_not_id integer,
  prm_top_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM notes.note WHERE not_id = prm_not_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_top_ids ISNULL THEN
    DELETE FROM notes.note_topic WHERE not_id = prm_not_id;
    RETURN;
  END IF;

  DELETE FROM notes.note_topic WHERE not_id = prm_not_id AND top_id <> ALL(prm_top_ids);

  FOREACH t IN ARRAY prm_top_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM notes.note_topic WHERE not_id = prm_not_id AND top_id = t) THEN
      INSERT INTO notes.note_topic (not_id, top_id) VALUES (prm_not_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION notes.note_set_topics(prm_token integer, prm_not_id integer, prm_top_ids integer[])
IS 'Set topics of a note';

CREATE OR REPLACE FUNCTION notes.note_set_dossiers(
  prm_token integer,
  prm_not_id integer,
  prm_dos_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM notes.note WHERE not_id = prm_not_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_dos_ids ISNULL THEN
    DELETE FROM notes.note_dossier WHERE not_id = prm_not_id;
    RETURN;
  END IF;

  DELETE FROM notes.note_dossier WHERE not_id = prm_not_id AND dos_id <> ALL(prm_dos_ids);

  FOREACH t IN ARRAY prm_dos_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM notes.note_dossier WHERE not_id = prm_not_id AND dos_id = t) THEN
      INSERT INTO notes.note_dossier (not_id, dos_id) VALUES (prm_not_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION notes.note_set_dossiers(prm_token integer, prm_not_id integer, prm_dos_ids integer[])
IS 'Set dossiers of a note';

CREATE OR REPLACE FUNCTION notes.note_get(prm_token integer, prm_not_id integer)
RETURNS notes.note
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret notes.note;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  SELECT * INTO ret FROM notes.note WHERE not_id = prm_not_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION notes.note_get(prm_token integer, prm_not_id integer) IS 'Returns information about a note';

CREATE OR REPLACE FUNCTION notes.note_topic_list(prm_token integer, prm_not_id integer)
RETURNS SETOF organ.topic
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  RETURN QUERY SELECT topic.* FROM organ.topic
    INNER JOIN notes.note_topic USING (top_id)
    WHERE not_id = prm_not_id
    ORDER BY top_name;
END;
$$;
COMMENT ON FUNCTION notes.note_topic_list(prm_token integer, prm_not_id integer) IS 'Retunrs the topics of a note';

CREATE OR REPLACE FUNCTION notes.note_dossier_list(prm_token integer, prm_not_id integer)
RETURNS SETOF organ.dossier
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  RETURN QUERY SELECT dossier.* FROM organ.dossier
    INNER JOIN notes.note_dossier USING (dos_id)
    WHERE not_id = prm_not_id
    ORDER BY dos_id;
END;
$$;
COMMENT ON FUNCTION notes.note_dossier_list(prm_token integer, prm_not_id integer) IS 'Retunrs the dossiers of a note';

-- 
-- JSON
-- 
CREATE OR REPLACE FUNCTION notes.note_topic_json(prm_token integer, prm_not_id integer, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
    FROM (SELECT
      CASE WHEN (req->>'top_id') IS NULL THEN NULL ELSE top_id END as top_id, 
      CASE WHEN (req->>'top_name') IS NULL THEN NULL ELSE  top_name END as top_name, 
      CASE WHEN (req->>'top_description') IS NULL THEN NULL ELSE top_description END as top_description,
      CASE WHEN (req->>'top_icon') IS NULL THEN NULL ELSE top_icon END as top_icon,
      CASE WHEN (req->>'top_color') IS NULL THEN NULL ELSE top_color END as top_color
      FROM organ.topic 
      INNER JOIN notes.note_topic USING (top_id) 
      WHERE not_id = prm_not_id
      ORDER BY top_name) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION notes.note_topic_json(prm_token integer, prm_not_id integer, req json) IS 'Returns the topics of a note as json';

CREATE OR REPLACE FUNCTION notes.note_dossier_json(prm_token integer, prm_not_id integer, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
    FROM (SELECT
      CASE WHEN (req->>'dos_id') IS NULL THEN NULL ELSE dos_id END as dos_id, 
      CASE WHEN (req->>'dos_firstname') IS NULL THEN NULL ELSE dos_firstname END as dos_firstname, 
      CASE WHEN (req->>'dos_lastname') IS NULL THEN NULL ELSE dos_lastname END as dos_lastname, 
      CASE WHEN (req->>'dos_birthdate') IS NULL THEN NULL ELSE dos_birthdate END as dos_birthdate, 
      CASE WHEN (req->>'dos_gender') IS NULL THEN NULL ELSE dos_gender END as dos_gender, 
      CASE WHEN (req->>'dos_grouped') IS NULL THEN NULL ELSE dos_grouped END as dos_grouped, 
      CASE WHEN (req->>'dos_external') IS NULL THEN NULL ELSE dos_external END as dos_external, 
      CASE WHEN (req->>'dos_groupname') IS NULL THEN NULL ELSE dos_groupname END as dos_groupname 
      FROM organ.dossier
      INNER JOIN notes.note_dossier USING (dos_id) 
      WHERE not_id = prm_not_id
      ORDER BY dos_id) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION notes.note_dossier_json(prm_token integer, prm_not_id integer, req json) IS 'Returns the dossiers of a note as json';

CREATE OR REPLACE FUNCTION notes.note_json(prm_token integer, prm_not_ids integer[], req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
  participant integer;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT par_id INTO participant FROM login.user WHERE usr_token = prm_token;
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
  FROM (SELECT 
    CASE WHEN (req->>'not_id') IS NULL THEN NULL ELSE not_id END as not_id, 
    CASE WHEN (req->>'not_text') IS NULL THEN NULL ELSE not_text END as not_text, 
    CASE WHEN (req->>'not_creation_date') IS NULL THEN NULL ELSE not_creation_date END as not_creation_date,
    CASE WHEN (req->>'not_event_date') IS NULL THEN NULL ELSE not_event_date END as not_event_date,
    CASE WHEN (req->>'not_object') IS NULL THEN NULL ELSE not_object END as not_object,
    CASE WHEN (req->>'nor_acknowledge_receipt') IS NULL THEN NULL ELSE
      (SELECT nor_acknowledge_receipt FROM notes.note_recipient WHERE par_id = participant AND note_recipient.not_id = note.not_id) END as nor_acknowledge_receipt,
    CASE WHEN (req->>'author') IS NULL THEN NULL ELSE 
      organ.participant_json(prm_token, not_author, req->'author') END AS author,
    CASE WHEN (req->>'topics') IS NULL THEN NULL ELSE
      notes.note_topic_json(prm_token, not_id, req->'topics') END as topics,
    CASE WHEN (req->>'dossiers') IS NULL THEN NULL ELSE
      notes.note_dossier_json(prm_token, not_id, req->'dossiers') END as dossiers,
    CASE WHEN (req->>'recipients') IS NULL THEN NULL ELSE
      notes.note_recipients_json(prm_token, not_id, req->'recipients', null) END as recipients,
    CASE WHEN (req->>'recipients_info') IS NULL THEN NULL ELSE
      notes.note_recipients_json(prm_token, not_id, req->'recipients_info', false) END as recipients_info,
    CASE WHEN (req->>'recipients_action') IS NULL THEN NULL ELSE
      notes.note_recipients_json(prm_token, not_id, req->'recipients_action', true) END as recipients_action
    FROM notes.note
    JOIN unnest(prm_not_ids) WITH ORDINALITY t(not_id, ord) USING (not_id)
      WHERE not_id = ANY(prm_not_ids)
      ORDER BY t.ord
  ) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION notes.note_json(prm_token integer, prm_not_ids integer[], req json) IS 'Returns information about a note as json';

CREATE OR REPLACE FUNCTION notes.note_in_view_list(
  prm_token integer, 
  prm_nov_id integer, 
  prm_grp_id integer, 
  req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  the_not_id integer;
  
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN notes.note_json(prm_token, (SELECT ARRAY(
   SELECT DISTINCT not_id FROM notes.note
    INNER JOIN notes.note_topic USING(not_id)
    INNER JOIN notes.notesview_topic USING(top_id)
    INNER JOIN notes.notesview USING(nov_id)
    INNER JOIN notes.note_dossier USING(not_id)
    INNER JOIN organ.dossiers_authorized_for_user(prm_token) 
      ON dossiers_authorized_for_user = note_dossier.dos_id
    WHERE nov_id = prm_nov_id AND
      (prm_grp_id IS NULL OR 
       prm_grp_id = ANY(SELECT grp_id FROM organ.dossier_assignment WHERE dossier_assignment.dos_id = note_dossier.dos_id)
    ))), req);
END;
$$;
COMMENT ON FUNCTION notes.note_in_view_list(
  prm_token integer, 
  prm_nov_id integer, 
  prm_grp_id integer, 
  req json)
 IS 'Returns the notes visible in a notes view';

CREATE OR REPLACE FUNCTION notes.note_delete(prm_token integer, prm_not_id integer)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  PERFORM notes.note_set_topics(prm_token, prm_not_id, NULL);
  PERFORM notes.note_set_dossiers(prm_token, prm_not_id, NULL);
  PERFORM notes.note_set_recipients(prm_token, prm_not_id, false, NULL);
  PERFORM notes.note_set_recipients(prm_token, prm_not_id, true, NULL);
  DELETE FROM notes.note WHERE not_id = prm_not_id;
END;
$$;
COMMENT ON FUNCTION notes.note_delete(prm_token integer, prm_not_id integer) IS 'Delete a note';

CREATE OR REPLACE FUNCTION notes.note_set_recipients(prm_token integer, prm_not_id integer, prm_for_action boolean, prm_par_ids integer[])
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  p integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM notes.note WHERE not_id = prm_not_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_par_ids ISNULL THEN
    RETURN;
  END IF;

  FOREACH p IN ARRAY prm_par_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM notes.note_recipient 
                     WHERE not_id = prm_not_id 
		     AND prm_for_action = nor_for_action 
		     AND par_id = p) THEN
      INSERT INTO notes.note_recipient (not_id, nor_for_action, par_id) VALUES (prm_not_id, prm_for_action, p);
    END IF;
  END LOOP;  
END;
$$;
COMMENT ON FUNCTION notes.note_set_recipients(prm_token integer, prm_not_id integer, prm_for_action boolean, prm_par_ids integer[]) IS 'Set recipients for a note, for information or action';

CREATE OR REPLACE FUNCTION notes.note_get_recipients(prm_token integer, prm_not_id integer, prm_for_action boolean)
RETURNS SETOF organ.participant
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  RETURN QUERY SELECT participant.*
    FROM organ.participant
    INNER JOIN notes.note_recipient USING(par_id)
    WHERE not_id = prm_not_id AND nor_for_action = prm_for_action;
END;
$$;
COMMENT ON FUNCTION notes.note_get_recipients(prm_token integer, prm_not_id integer, prm_for_action boolean) IS 'Get recipients for a note for information or action';

CREATE OR REPLACE FUNCTION notes.note_recipients_json(prm_token integer, prm_not_id integer, req json, prm_for_action boolean)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  RAISE WARNING '%', req;
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
    FROM (SELECT
      CASE WHEN (req->>'par_id') IS NULL THEN NULL ELSE par_id END as par_id, 
      CASE WHEN (req->>'par_firstname') IS NULL THEN NULL ELSE  par_firstname END as par_firstname, 
      CASE WHEN (req->>'par_lastname') IS NULL THEN NULL ELSE  par_lastname END as par_lastname, 
      CASE WHEN (req->>'par_email') IS NULL THEN NULL ELSE par_email END as par_email,
      CASE WHEN (req->>'nor_for_action') IS NULL THEN NULL ELSE nor_for_action END as nor_for_action,
      CASE WHEN (req->>'nor_acknowledge_receipt') IS NULL THEN NULL ELSE nor_acknowledge_receipt END as nor_acknowledge_receipt
      FROM notes.note_recipient INNER JOIN organ.participant USING(par_id)
      WHERE not_id = prm_not_id
      AND CASE WHEN prm_for_action IS NULL THEN TRUE ELSE nor_for_action = prm_for_action END) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION notes.note_recipients_json(prm_token integer, prm_not_id integer, req json, prm_for_action boolean)
 IS 'Returns the recipients for a note as json, either all recipients or depending on for_action field';

CREATE OR REPLACE FUNCTION notes.note_participant_list(prm_token integer, prm_column_ordering text, prm_desc boolean, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
  participant integer;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT par_id INTO participant FROM login.user WHERE usr_token = prm_token;
  RETURN notes.note_json(prm_token, (SELECT ARRAY(
      SELECT *
      FROM public._format_retrieve_ids(participant, 'notes', prm_column_ordering, CASE prm_desc WHEN TRUE THEN 'DESC' ELSE 'ASC' END)
    )), req);
END;
$$;
COMMENT ON FUNCTION notes.note_participant_list(prm_token integer, prm_column_ordering text, prm_desc boolean, req json) IS 'Return the notes created or destinated to the current logged user';

DROP FUNCTION IF EXISTS notes._retrieve_notes_participant(prm_par_id integer);
DROP TYPE IF EXISTS notes.notes_retrieved;
CREATE TYPE notes.notes_retrieved AS (
  not_id integer,
  not_creation_date timestamp with time zone,
  not_event_date timestamp with time zone
);

CREATE FUNCTION notes._retrieve_notes_participant(prm_par_id integer)
RETURNS SETOF notes.notes_retrieved
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
    SELECT DISTINCT ON (not_id) not_id,
      not_creation_date,
      CASE WHEN not_event_date IS NULL THEN not_creation_date ELSE not_event_date END as not_event_date
    FROM notes.note
    LEFT OUTER JOIN notes.note_recipient USING(not_id)
    WHERE note.not_author = prm_par_id or note_recipient.par_id = prm_par_id;
END;
$$;
COMMENT ON FUNCTION notes._retrieve_notes_participant(prm_par_id integer) IS 'Returns the list of notes related to a participant';

CREATE OR REPLACE FUNCTION notes.note_user_acknowledge_receipt(prm_token integer, prm_not_id integer)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  participant integer;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT par_id INTO participant FROM login.user WHERE usr_token = prm_token;
  UPDATE notes.note_recipient SET nor_acknowledge_receipt = TRUE WHERE not_id = prm_not_id AND par_id = participant;
END;
$$;
COMMENT ON FUNCTION notes.note_user_acknowledge_receipt(prm_token integer, prm_not_id integer) IS 'The user asserted that he read the note';
