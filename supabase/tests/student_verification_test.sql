BEGIN;
SET LOCAL session_replication_role = replica;  -- orders triggers do HTTP
CREATE TEMP TABLE t(step INT, scenario TEXT, expected TEXT, actual TEXT, pass BOOLEAN) ON COMMIT DROP;
GRANT ALL ON t TO anon, authenticated;

DO $t$
DECLARE
  v_admin UUID; v_student UUID; v_driver UUID; v_other UUID;
  v_schoolA UUID; v_schoolX UUID;
  v_order UUID := 'aaaaaaaa-0000-0000-0000-0000000f5001';
  v_ver UUID; v_row public.student_verifications; r JSONB;
BEGIN
  SELECT id INTO v_admin FROM public.users WHERE role='admin' LIMIT 1;
  SELECT id INTO v_student FROM public.users WHERE role='customer' LIMIT 1;
  SELECT id INTO v_driver FROM public.users WHERE role='customer' AND id<>v_student LIMIT 1;
  SELECT id INTO v_other FROM public.users WHERE role='customer' AND id NOT IN (v_student,v_driver) LIMIT 1;
  INSERT INTO public.schools(name,address,is_active) VALUES ('Kingston High','1 King St',TRUE) RETURNING id INTO v_schoolA;
  INSERT INTO public.schools(name,address,is_active) VALUES ('Closed Academy','2 Old Rd',FALSE) RETURNING id INTO v_schoolX;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_student,'role','authenticated')::text, true);

  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolA,'student-ids/'||v_student||'/id.jpg', NULL);
  INSERT INTO t VALUES (1,'submit -> processing','processing',
    (SELECT verification_status FROM public.student_verifications WHERE id=v_ver),
    (SELECT verification_status FROM public.student_verifications WHERE id=v_ver)='processing');

  v_row := public.finalize_student_verification(v_ver,'JOHN SCOTT','STU 12345','Kingston High Charter', current_date-100, current_date+300,'DOC1',88);
  INSERT INTO t VALUES (2,'finalize good -> approved','approved/t',
    v_row.verification_status||'/'||v_row.benefits_active, v_row.verification_status='approved' AND v_row.benefits_active);
  INSERT INTO t VALUES (3,'benefits_active after approve','t',
    public.student_benefits_active(v_student)::text, public.student_benefits_active(v_student));

  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolA,'student-ids/'||v_student||'/id2.jpg',NULL);
  v_row := public.finalize_student_verification(v_ver,'John Scott','STU12345','Kingston High',current_date-500,current_date-1,'DOC1',90);
  INSERT INTO t VALUES (4,'expired ID -> needs_update','needs_update',v_row.verification_status,v_row.verification_status='needs_update');

  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolA,'student-ids/'||v_student||'/id3.jpg',NULL);
  v_row := public.finalize_student_verification(v_ver,'John Scott','WRONG999','Kingston High',current_date-10,current_date+300,'DOC1',90);
  INSERT INTO t VALUES (5,'id mismatch -> manual_review','manual_review',v_row.verification_status,v_row.verification_status='manual_review');

  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolX,'student-ids/'||v_student||'/id4.jpg',NULL);
  v_row := public.finalize_student_verification(v_ver,'John Scott','STU12345','Closed Academy',current_date-10,current_date+300,'DOC1',90);
  INSERT INTO t VALUES (6,'inactive school -> rejected','rejected',v_row.verification_status,v_row.verification_status='rejected');

  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolA,'student-ids/'||v_student||'/id5.jpg',NULL);
  v_row := public.finalize_student_verification(v_ver,'John Scott','STU12345','Kingston High',current_date-10,current_date+300,'DOC1',20);
  INSERT INTO t VALUES (7,'low confidence -> needs_update','needs_update',v_row.verification_status,v_row.verification_status='needs_update');

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_other,'role','authenticated')::text, true);
  BEGIN
    PERFORM public.submit_student_verification(v_student,'X','Y',v_schoolA,'x',NULL);
    INSERT INTO t VALUES (8,'non-owner submit','forbidden','worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (8,'non-owner submit','forbidden',SQLERRM,SQLERRM ILIKE '%Forbidden%');
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_student,'role','authenticated')::text, true);
  v_ver := public.submit_student_verification(v_student,'John Scott','STU12345',v_schoolA,'student-ids/'||v_student||'/id6.jpg',NULL);
  PERFORM public.finalize_student_verification(v_ver,'John Scott','STU12345','Kingston High',current_date-10,current_date+300,'DOC1',90);

  INSERT INTO public.orders(id,user_id,restaurant_id,delivery_address,subtotal,delivery_fee,total_amount,payment_method,status,ordered_at,recipient_type,student_id,school_id,driver_id)
  VALUES (v_order,v_student,(SELECT id FROM public.restaurants LIMIT 1),'QA',100,0,100,'cash','preparing',now(),'student',v_student,v_schoolA,v_driver);

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_driver,'role','authenticated')::text, true);
  r := public.confirm_student_delivery(v_order, TRUE, NULL);
  INSERT INTO t VALUES (9,'driver YES -> confirmed & kept','confirmed/t',
    (r->>'status')||'/'||public.student_benefits_active(v_student)::text,
    r->>'status'='confirmed' AND public.student_benefits_active(v_student));

  INSERT INTO public.orders(id,user_id,restaurant_id,delivery_address,subtotal,delivery_fee,total_amount,payment_method,status,ordered_at,recipient_type,student_id,school_id,driver_id)
  VALUES ('aaaaaaaa-0000-0000-0000-0000000f5002',v_student,(SELECT id FROM public.restaurants LIMIT 1),'QA',100,0,100,'cash','preparing',now(),'student',v_student,v_schoolA,v_driver);
  r := public.confirm_student_delivery('aaaaaaaa-0000-0000-0000-0000000f5002', FALSE, 'left at home');
  INSERT INTO t VALUES (10,'driver NO -> suspended','suspended',r->>'status',r->>'status'='suspended');
  INSERT INTO t VALUES (11,'benefits off after NO','t',(NOT public.student_benefits_active(v_student))::text, NOT public.student_benefits_active(v_student));
  INSERT INTO t VALUES (12,'review pending row','1',
    (SELECT count(*)::text FROM public.student_delivery_reviews WHERE student_id=v_student AND status='pending'),
    (SELECT count(*) FROM public.student_delivery_reviews WHERE student_id=v_student AND status='pending')=1);

  BEGIN
    PERFORM public.admin_resolve_student_review((SELECT id FROM public.student_delivery_reviews WHERE student_id=v_student LIMIT 1),'restore',NULL);
    INSERT INTO t VALUES (13,'driver resolve review','forbidden','worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (13,'driver resolve review','forbidden',SQLERRM,SQLERRM ILIKE '%Forbidden%');
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
  r := public.admin_resolve_student_review((SELECT id FROM public.student_delivery_reviews WHERE student_id=v_student LIMIT 1),'restore','looked ok');
  INSERT INTO t VALUES (14,'admin restore -> benefits on','resolved/t',
    (r->>'status')||'/'||public.student_benefits_active(v_student)::text,
    r->>'status'='resolved' AND public.student_benefits_active(v_student));

  UPDATE public.student_verifications SET expires_at = now()-interval '1 day'
    WHERE user_id=v_student AND benefits_active=TRUE;
  PERFORM public.expire_student_verifications();
  INSERT INTO t VALUES (15,'expiry sweep -> benefits off','t',(NOT public.student_benefits_active(v_student))::text, NOT public.student_benefits_active(v_student));
END $t$;

SELECT jsonb_pretty(jsonb_agg(jsonb_build_object('step',step,'scenario',scenario,'expected',expected,'actual',actual,
  'result',CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END) ORDER BY step)) FROM t;
SELECT count(*) FILTER (WHERE pass) passed, count(*) FILTER (WHERE NOT pass) failed, count(*) total FROM t;
ROLLBACK;
