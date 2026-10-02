import {adminService} from '../../helpers/adminService';
export async function handle(request:Request){return adminService.handle(request,'GET');}
