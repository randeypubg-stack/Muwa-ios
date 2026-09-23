import {schema} from './original_POST.schema';
import {subtitleV2Service} from '../../helpers/subtitleV2Service';
export async function handle(request:Request) {
 const parsed=schema.safeParse(await request.json().catch(()=>null));
 if(!parsed.success)return Response.json({error:'Нужен поддерживаемый аудиофайл длительностью до 10 минут.',code:'INVALID_INPUT'},{status:400});
 return subtitleV2Service.execute(request,'original',parsed.data);
}
