import {adminValidation,type AdminAction,type AdminResult} from '../../helpers/adminValidation';
export const schema=adminValidation.action;
export type InputType=AdminAction;
export type OutputType=AdminResult;
export async function postAdminAction(body:InputType,init?:RequestInit):Promise<OutputType>{
 const response=await fetch('/_api/admin/action',{...init,method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json',...init?.headers},body:JSON.stringify(schema.parse(body))});
 const data=await response.json();
 if(!response.ok)throw new Error(data.error??'Не удалось выполнить действие.');
 return data;
}
