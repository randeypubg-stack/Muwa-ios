import {schema} from './access_POST.schema';
import {premiumService} from '../../helpers/premiumService';
export async function handle(request:Request) { return premiumService.handle(request,schema); }
