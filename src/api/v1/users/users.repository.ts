import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";

@Injectable()
export class UsersRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'users',
            searchableColumns: ['first_name', 'last_name', 'email'],
            sortableColumns: ['id', 'first_name', 'last_name', 'created_at', 'updated_at'],
            filterableColumns: ['role_id', 'id', 'status'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }


    async deleteUser(userId: number | string): Promise<any | null> {

        await this.database_service.query(
            `DELETE FROM refresh_tokens WHERE user_id = $1`,
            [userId],
        );

        const result = await this.database_service.query<any>(
            `DELETE FROM users WHERE id = $1 RETURNING *`,
            [userId],
        );

        return result.rows[0] || null;
    }


}