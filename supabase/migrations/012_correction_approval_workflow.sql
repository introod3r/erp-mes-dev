-- Correction approval workflow foundation.
-- Apply after 011_rls_hardening_critical_tables.sql

CREATE TABLE IF NOT EXISTS public.correction_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  request_number text NOT NULL,
  correction_type text NOT NULL CHECK (correction_type IN ('INVENTORY_TRANSACTION','PRODUCTION_CONSUMPTION','PRODUCTION_RECEIPT','OPERATION_EVENT')),
  target_id uuid NOT NULL,
  reason text NOT NULL,
  status text NOT NULL CHECK (status IN ('REQUESTED','APPROVED','REJECTED','EXECUTED','CANCELLED')) DEFAULT 'REQUESTED',
  requested_by uuid REFERENCES auth.users(id),
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  executed_by uuid REFERENCES auth.users(id),
  executed_at timestamptz,
  result_reference_id uuid,
  review_note text,
  UNIQUE(company_id, request_number)
);
CREATE INDEX IF NOT EXISTS idx_correction_requests_company_status ON public.correction_requests(company_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_correction_requests_target ON public.correction_requests(correction_type, target_id);

ALTER TABLE public.correction_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY correction_requests_member_select ON public.correction_requests FOR SELECT USING (public.is_company_member(company_id));

CREATE OR REPLACE FUNCTION public.create_correction_request(
  p_company_id uuid,
  p_request_number text,
  p_correction_type text,
  p_target_id uuid,
  p_reason text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','MANAGER','PLANNER','WAREHOUSE','PRODUCTION_OPERATOR','QUALITY']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF trim(COALESCE(p_request_number,'')) = '' THEN RAISE EXCEPTION 'Request number is required'; END IF;
  IF trim(COALESCE(p_reason,'')) = '' THEN RAISE EXCEPTION 'Reason is required'; END IF;

  INSERT INTO public.correction_requests(company_id, request_number, correction_type, target_id, reason, requested_by)
  VALUES(p_company_id, trim(p_request_number), p_correction_type, p_target_id, p_reason, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_correction_request(
  p_request_id uuid,
  p_approve boolean,
  p_review_note text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req public.correction_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM public.correction_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Correction request not found'; END IF;
  IF NOT public.has_company_role(v_req.company_id, ARRAY['ADMIN','MANAGER']) THEN
    RAISE EXCEPTION 'Only ADMIN/MANAGER can review correction requests' USING ERRCODE='42501';
  END IF;
  IF v_req.status <> 'REQUESTED' THEN RAISE EXCEPTION 'Only REQUESTED corrections can be reviewed'; END IF;

  UPDATE public.correction_requests
  SET status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
      reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_review_note
  WHERE id = p_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.execute_correction_request(p_request_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_req public.correction_requests%ROWTYPE;
  v_result uuid;
BEGIN
  SELECT * INTO v_req FROM public.correction_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Correction request not found'; END IF;
  IF NOT public.has_company_role(v_req.company_id, ARRAY['ADMIN','MANAGER']) THEN
    RAISE EXCEPTION 'Only ADMIN/MANAGER can execute correction requests' USING ERRCODE='42501';
  END IF;
  IF v_req.status <> 'APPROVED' THEN RAISE EXCEPTION 'Correction request must be APPROVED before execution'; END IF;

  IF v_req.correction_type = 'INVENTORY_TRANSACTION' THEN
    v_result := public.reverse_inventory_transaction(v_req.target_id, v_req.reason);
  ELSIF v_req.correction_type = 'PRODUCTION_CONSUMPTION' THEN
    v_result := public.reverse_production_consumption(v_req.target_id, v_req.reason);
  ELSIF v_req.correction_type = 'PRODUCTION_RECEIPT' THEN
    v_result := public.reverse_production_receipt(v_req.target_id, v_req.reason);
  ELSIF v_req.correction_type = 'OPERATION_EVENT' THEN
    PERFORM public.reverse_operation_event(v_req.target_id, v_req.reason);
    v_result := v_req.target_id;
  ELSE
    RAISE EXCEPTION 'Unsupported correction type %', v_req.correction_type;
  END IF;

  UPDATE public.correction_requests
  SET status = 'EXECUTED', executed_by = auth.uid(), executed_at = now(), result_reference_id = v_result
  WHERE id = v_req.id;

  RETURN v_result;
END;
$$;
