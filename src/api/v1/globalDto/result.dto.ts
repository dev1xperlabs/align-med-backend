export class ResultDto<T = any> {
    statusCode: string;
    resultMessage: string;
    error?: string;
    errorMessage?: string;
    result?: T;

    constructor(partial: Partial<ResultDto<T>>) {
        Object.assign(this, partial);
    }
}
