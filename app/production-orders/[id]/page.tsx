import { ProductionOrderDetail } from '@/components/ProductionOrderDetail';

export default async function ProductionOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ProductionOrderDetail id={id} />;
}
