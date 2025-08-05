import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { DatabaseService } from '../../../../database/database.service';
import { JWT_SECRET } from '../constants';
import { TokenPayload } from '../interfaces/token-payload.interface';
import { ResponseUserDto } from '../interfaces/user.interface';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly databaseService: DatabaseService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: JWT_SECRET,
    });
  }

  async validate(payload: TokenPayload): Promise<ResponseUserDto> {
    const { rows } = await this.databaseService.query(
      'SELECT id, email, created_at, updated_at FROM users WHERE id = $1',
      [payload.userId],
    );

    if (!rows.length) {
      throw new Error('User not found');
    }

    return rows[0];
  }
}
