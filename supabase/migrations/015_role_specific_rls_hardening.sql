-- Additional role-specific RLS hardening for master/engineering tables.
-- Apply after 014_inspection_module.sql

-- Drop broad staff policies created by base migration for selected non-ledger tables.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'items','units_of_measure','unit_conversions','warehouses','warehouse_locations','lots',
    'boms','bom_lines','work_centers','machines','routings','routing_operations',
    'production_orders','production_order_materials','production_order_operations',
    'scrap_reason_codes','downtime_reason_codes','inspection_plans','inspection_characteristics','quality_inspections','inspection_results','correction_requests'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_staff_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_staff_update', t);
  END LOOP;
END $$;

-- Master data: ADMIN/MANAGER/PLANNER
CREATE POLICY items_master_insert ON public.items FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY items_master_update ON public.items FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY uom_master_insert ON public.units_of_measure FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY uom_master_update ON public.units_of_measure FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY warehouses_master_insert ON public.warehouses FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE']));
CREATE POLICY warehouses_master_update ON public.warehouses FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE']));
CREATE POLICY locations_master_insert ON public.warehouse_locations FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE']));
CREATE POLICY locations_master_update ON public.warehouse_locations FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE']));
CREATE POLICY lots_warehouse_insert ON public.lots FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE','QUALITY']));
CREATE POLICY lots_warehouse_update ON public.lots FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE','QUALITY'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','WAREHOUSE','QUALITY']));

-- Engineering: ADMIN/MANAGER/PLANNER
CREATE POLICY boms_eng_insert ON public.boms FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY boms_eng_update ON public.boms FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY bom_lines_eng_insert ON public.bom_lines FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY bom_lines_eng_update ON public.bom_lines FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY routings_eng_insert ON public.routings FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY routings_eng_update ON public.routings FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY routing_ops_eng_insert ON public.routing_operations FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY routing_ops_eng_update ON public.routing_operations FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));

-- Resources: ADMIN/MANAGER/PLANNER
CREATE POLICY wc_res_insert ON public.work_centers FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY wc_res_update ON public.work_centers FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY machines_res_insert ON public.machines FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY machines_res_update ON public.machines FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER','PRODUCTION_OPERATOR'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER','PRODUCTION_OPERATOR']));

-- Planning tables: creation by planners, execution updates mostly through RPC.
CREATE POLICY po_planning_insert ON public.production_orders FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));
CREATE POLICY po_planning_update ON public.production_orders FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','PLANNER']));

-- Quality master and inspections.
CREATE POLICY scrap_reasons_quality_insert ON public.scrap_reason_codes FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY scrap_reasons_quality_update ON public.scrap_reason_codes FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY downtime_reasons_quality_insert ON public.downtime_reason_codes FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY downtime_reasons_quality_update ON public.downtime_reason_codes FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));

CREATE POLICY inspection_plans_quality_insert ON public.inspection_plans FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY inspection_plans_quality_update ON public.inspection_plans FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY inspection_chars_quality_insert ON public.inspection_characteristics FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
CREATE POLICY inspection_chars_quality_update ON public.inspection_characteristics FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','MANAGER','QUALITY']));
