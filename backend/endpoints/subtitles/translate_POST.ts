import {schema} from './translate_POST.schema';
import {subtitleV2Service} from '../../helpers/subtitleV2Service';
export async function handle(request:Request) {
 const parsed=schema.safeParse(await request.json().catch(()=>null));
 if(!parsed.success)return Response.json({error:'Неверный язык или документ.',code:'INVALID_INPUT'},{status:400});
 return subtitleV2Service.execute(request,'translation',parsed.data);
}
