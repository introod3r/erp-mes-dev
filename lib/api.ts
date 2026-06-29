import { z } from 'zod';

export const uuidSchema = z.string().uuid();

export const itemCreateSchema = z.object({
  company_id: uuidSchema,
  item_code: z.string().min(1).max(80),
  item_type: z.enum(['RAW_MATERIAL', 'SEMI_FINISHED', 'FINISHED_GOOD', 'CONSUMABLE', 'SERVICE']),
  default_uom_id: uuidSchema,
  name: z.string().min(1).max(255),
  description: z.string().optional().nullable(),
  is_stocked: z.boolean().default(true),
  is_purchased: z.boolean().default(false),
  is_manufactured: z.boolean().default(false),
  is_sellable: z.boolean().default(false),
  is_lot_tracked: z.boolean().default(false),
});

export const warehouseCreateSchema = z.object({
  company_id: uuidSchema,
  code: z.string().min(1).max(80),
  name: z.string().min(1).max(255),
  warehouse_type: z.enum(['RAW_MATERIAL', 'WIP', 'FINISHED_GOODS', 'SCRAP', 'QUALITY', 'GENERAL', 'SUBCONTRACTOR']),
});

export const productionOrderCreateSchema = z.object({
  company_id: uuidSchema,
  order_number: z.string().min(1).max(80),
  item_id: uuidSchema,
  bom_id: uuidSchema.optional().nullable(),
  routing_id: uuidSchema.optional().nullable(),
  planned_quantity: z.number().positive(),
  uom_id: uuidSchema,
  planned_start_date: z.string().datetime().optional().nullable(),
  planned_end_date: z.string().datetime().optional().nullable(),
  priority: z.number().int().default(100),
});
