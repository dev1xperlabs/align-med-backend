export const JWT_SECRET = process.env.JWT_SECRET || 'very-secret-key';
export const JWT_EXPIRATION = 24;
export const REFRESH_TOKEN_EXPIRATION_DAYS = 7;







export enum UserRole {
    ADMIN = 1,
    USER = 2,
}