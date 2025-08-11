import { User } from "../../auth/interfaces/user.interface";
import { BaseListModel } from "../../shared/base-list.dto";
import { UserListItemDto } from "./user-list.item.dto";

export class UserListDto extends BaseListModel<UserListItemDto> {
}