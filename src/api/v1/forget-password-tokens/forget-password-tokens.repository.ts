import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";
import { ValidateAccessToken } from "./dto/validate-token.dto";
import { CreateForgetPasswordTokensDto } from "./dto/create-forget-password-tokens.dto";

@Injectable()
export class ForgetpasswordRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'forget_password_tokens',
            searchableColumns: ['id', 'token'],
            sortableColumns: ['id', 'created_at', 'updated_at'],
            filterableColumns: ['id'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }




    async createForgetPasswordToken(token: string): Promise<void> {
        const now = new Date();

        await this.database_service.query(
            'INSERT INTO forget_password_tokens (token, created_at, updated_at) VALUES ($1, $2, $3)',
            [token, now, now],
        );
    }


    async validateAccessToken(token: string): Promise<boolean> {
        const result = await this.database_service.query(
            'SELECT * FROM forget_password_tokens WHERE token = $1',
            [token],
        );
        return result.rows.length > 0;
    }



    async deleteTokenByToken(token: string): Promise<any | null> {
        const result = await this.database_service.query(
            `DELETE FROM forget_password_tokens WHERE token = $1 RETURNING *`,
            [token],
        );

        return result.rows[0] || null;
    }


}