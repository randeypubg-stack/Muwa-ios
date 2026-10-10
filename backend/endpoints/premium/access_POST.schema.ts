import { z } from 'zod';
export const schema = z.discriminatedUnion('action', [
  z.object({action:z.literal('status')}),
  z.object({action:z.literal('redeem'),code:z.string().min(1).max(80)}),
  z.object({action:z.literal('list')}),
  z.object({action:z.literal('create'),label:z.string().trim().min(1).max(60),durationDays:z.number().int().min(1).max(365),maxUses:z.number().int().min(1).max(1000),validDays:z.number().int().min(1).max(365)}),
  z.object({action:z.literal('disable'),id:z.string().uuid()})
]);
export type InputType = z.infer<typeof schema>;
export interface PremiumStatus {userId:number;isPremium:boolean;expiresAt:string|null;canManageCodes:boolean}
export interface GiftCode {id:string;label:string;durationDays:number;maxUses:number;uses:number;expiresAt:string;disabled:boolean}
export type OutputType = PremiumStatus & {codes?:GiftCode[];code?:string;alreadyRedeemed?:boolean};
export async function postPremiumAccess(body:InputType, init?:RequestInit):Promise<OutputType> {
  const response=await fetch('/_api/premium/access',{...init,method:'POST',headers:{'Content-Type':'application/json',...init?.headers},body:JSON.stringify(body)});
  const result=await response.json();
  if(!response.ok)throw new Error(result.error || 'Не удалось выполнить запрос');
  return result;
}
